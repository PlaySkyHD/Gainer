import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../domain/models/cardio/cardio_draft.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';
import 'cardio_preferences.dart';

const cardioSessionAggregateType = 'cardio-session';

/// Schlüssel des laufenden Entwurfs in den Sync-Metadaten.
const cardioDraftMetadataKey = 'cardio-active-session';

/// Höchstzahl RR-Werte je Einheit laut Server.
const _maxRrValues = 40000;

/// Obergrenzen der manuellen Ergometerwerte laut Server.
const maxDistanceKm = 1000.0;
const maxPowerWatts = 3000.0;
const maxEnergyKcal = 20000.0;

typedef CardioIdFactory = String Function();

/// Die Einheit ist schon gespeichert, etwa weil nach dem Speichern das Löschen
/// des Entwurfs scheiterte. Aufrufer behandeln sie als gespeichert.
class CardioSessionExistsException extends StateError {
  CardioSessionExistsException(this.sessionId)
    : super('Die Cardio-Einheit existiert bereits.');

  final String sessionId;
}

/// Local-first Cardio-Einheiten über die Outbox des kontogebundenen Speichers
/// sowie der laufende Entwurf.
class CardioRepository {
  CardioRepository({
    required this.store,
    CardioIdFactory? ids,
    DateTime Function()? clock,
  }) : ids = ids ?? _newUuidV4,
       clock = clock ?? DateTime.now,
       preferences = CardioPreferences(store: store);

  final LocalSyncStore store;
  final CardioIdFactory ids;
  final DateTime Function() clock;

  /// Cardio-Einstellungen desselben Kontos.
  final CardioPreferences preferences;

  final ValueNotifier<int> _revision = ValueNotifier(0);

  /// Meldet jede lokale Änderung an Einheiten (Speichern, Ändern, Löschen)
  /// und gezogene Änderungen ([notifyExternalChange]), damit Listen wie das
  /// Tagebuch neu laden.
  ValueListenable<int> get changes => _revision;

  void _changed() => _revision.value++;

  /// Einheiten haben sich außerhalb dieses Repositorys geändert, etwa durch
  /// einen Sync-Pull von einem anderen Gerät.
  void notifyExternalChange() => _changed();

  /// Neue Einheiten-ID (UUID v4).
  String newSessionId() => ids();

  /// Gibt es die Einheit lokal, auch gelöscht?
  Future<bool> hasSession(String id) async =>
      await store.readAggregate(cardioSessionAggregateType, id) != null;

  /// Nicht gelöschte Einheiten, neueste zuerst.
  Future<List<CardioSession>> readSessions() async {
    final rows = await store.readAggregates(cardioSessionAggregateType);
    final sessions = [
      for (final row in rows) CardioSession.fromJson(_map(row.workingCopy)),
    ].where((session) => session.deletedAtUtc == null).toList();
    sessions.sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
    return List.unmodifiable(sessions);
  }

  Future<CardioSession?> readSession(String id) async {
    final row = await store.readAggregate(cardioSessionAggregateType, id);
    if (row == null) return null;
    final session = CardioSession.fromJson(_map(row.workingCopy));
    return session.deletedAtUtc == null ? session : null;
  }

  /// Server-Version der Einheit; null, solange sie nicht synchronisiert ist.
  Future<int?> serverVersionOf(String id) async {
    final version = (await store.readAggregate(
      cardioSessionAggregateType,
      id,
    ))?.serverVersion;
    return version != null && version > 0 ? version : null;
  }

  /// Speichert eine beendete Einheit (Operation `create`). Erstellt-/
  /// Änderungszeit setzt das Repository. Pulswerte außerhalb 25–250 werden zu 0
  /// und RR-Werte außerhalb 200–3000 ms entfallen, weil der Server sie ablehnt.
  Future<CardioSession> saveFinished(CardioSession session) async {
    final now = _roundToSecond(clock());
    final saved = sanitize(session, now: now);
    if (await hasSession(saved.sessionId)) {
      throw CardioSessionExistsException(saved.sessionId);
    }
    final body = saved.toJson();
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: cardioSessionAggregateType,
      aggregateId: saved.sessionId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: body,
      envelope: localEnvelope(aggregateId: saved.sessionId, workingCopy: body),
      createdAtUtc: now,
    );
    _changed();
    return saved;
  }

  /// Macht eine Einheit serverkonform, weil der Server sonst die ganze Einheit
  /// mit `validation_failed` ablehnt: Pulswerte außerhalb 25–250 werden 0, RR-
  /// Werte außerhalb 200–3000 ms entfallen (höchstens 40 000), die Pulsreihe
  /// hat höchstens `ceil(Dauer / Intervall) + 1` Werte, Ende liegt nach Start
  /// und höchstens 24 h danach, ungültige Zonen und Ergometerwerte entfallen,
  /// Gurtname, Vorlagenname und Notiz werden gekürzt; ungültige Phasenlisten
  /// (mehr als 30, überlappend, Dauer, Zone, über 4 h) entfallen ganz.
  static CardioSession sanitize(CardioSession session, {DateTime? now}) {
    final stamp = now ?? session.updatedAtUtc;
    final started = session.startedAtUtc.toUtc();
    final ended = _clampedEnd(started, session.endedAtUtc.toUtc());
    final interval = session.sampleIntervalSeconds.clamp(1, 60);
    final maxValues =
        (ended.difference(started).inSeconds / interval).ceil() + 1;
    final phases = [
      for (final phase in session.phases)
        CardioPhase(
          startOffsetSeconds: phase.startOffsetSeconds,
          durationSeconds: phase.durationSeconds,
          name: phase.name.trim(),
          lowBpm: phase.lowBpm,
          highBpm: phase.highBpm,
        ),
    ];
    return CardioSession(
      sessionId: session.sessionId,
      activityType: session.activityType,
      startedAtUtc: started,
      endedAtUtc: ended,
      targetZone: session.targetZone?.isValid == true
          ? session.targetZone
          : null,
      sampleIntervalSeconds: interval,
      heartRateBpm: [
        for (final bpm in session.heartRateBpm)
          bpm >= 25 && bpm <= 250 ? bpm : 0,
      ].take(maxValues).toList(),
      rrIntervalsMs: [
        for (final rr in session.rrIntervalsMs)
          if (rr >= 200 && rr <= 3000) rr,
      ].take(_maxRrValues).toList(),
      sensorName: _trimmedOrNull(session.sensorName, 100),
      distanceKm: _withinOrNull(session.distanceKm, maxDistanceKm),
      averagePowerWatts: _withinOrNull(
        session.averagePowerWatts,
        maxPowerWatts,
      ),
      energyKcal: _withinOrNull(session.energyKcal, maxEnergyKcal),
      notes: _trimmedOrNull(session.notes, 2000),
      recoveryStartBpm: _validRecovery(session)
          ? session.recoveryStartBpm
          : null,
      recoveryEndBpm: _validRecovery(session) ? session.recoveryEndBpm : null,
      templateName: _trimmedOrNull(session.templateName, 100),
      phases: CardioPhase.isValidList(phases) ? phases : const [],
      createdAtUtc: stamp,
      updatedAtUtc: stamp,
    );
  }

  /// Ende nach Start und höchstens 24 h danach.
  static DateTime _clampedEnd(DateTime started, DateTime end) {
    var ended = end;
    if (!ended.isAfter(started)) {
      ended = started.add(const Duration(seconds: 1));
    }
    const maxDuration = Duration(hours: 24);
    if (ended.difference(started) > maxDuration) {
      ended = started.add(maxDuration);
    }
    return ended;
  }

  static double? _withinOrNull(double? value, double max) =>
      value != null && value.isFinite && value >= 0 && value <= max
      ? value
      : null;

  /// Gekürzter Text; leer oder null ergibt null.
  static String? _trimmedOrNull(String? raw, int maxLength) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return value.length > maxLength ? value.substring(0, maxLength) : value;
  }

  /// Beide Erholungswerte vorhanden und 25–250.
  static bool _validRecovery(CardioSession session) {
    bool ok(int? bpm) => bpm != null && bpm >= 25 && bpm <= 250;
    return ok(session.recoveryStartBpm) && ok(session.recoveryEndBpm);
  }

  /// Ersetzt Ergometerwerte und Notiz (Operation `update`). `null` löscht den
  /// Wert. Leere Notizen entfallen.
  Future<CardioSession> updateDetails(
    String id, {
    double? distanceKm,
    double? averagePowerWatts,
    double? energyKcal,
    String? notes,
  }) async {
    final old = await _required(id);
    final current = CardioSession.fromJson(_map(old.workingCopy));
    if (current.deletedAtUtc != null) {
      throw StateError('Die Cardio-Einheit ist gelöscht.');
    }
    final trimmed = notes?.trim();
    final note = trimmed == null || trimmed.isEmpty ? null : trimmed;
    for (final (value, max) in [
      (distanceKm, maxDistanceKm),
      (averagePowerWatts, maxPowerWatts),
      (energyKcal, maxEnergyKcal),
    ]) {
      if (value != null && (!value.isFinite || value < 0 || value > max)) {
        throw ArgumentError.value(
          value,
          'value',
          'Werte müssen zwischen 0 und $max liegen.',
        );
      }
    }
    if (note != null && note.length > 2000) {
      throw ArgumentError.value(notes, 'notes', 'Höchstens 2000 Zeichen.');
    }
    final updated = current.copyWith(
      distanceKm: () => distanceKm,
      averagePowerWatts: () => averagePowerWatts,
      energyKcal: () => energyKcal,
      notes: () => note,
      updatedAtUtc: _roundToSecond(clock()),
    );
    final body = updated.toJson();
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: cardioSessionAggregateType,
      aggregateId: id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(old, body),
      createdAtUtc: clock().toUtc(),
    );
    _changed();
    return updated;
  }

  /// Speichert die Erholungswerte (Puls beim Beenden und 60 s später) als
  /// Operation `update`. Beide Werte müssen zwischen 25 und 250 liegen.
  Future<CardioSession> saveRecovery(
    String id, {
    required int startBpm,
    required int endBpm,
  }) async {
    for (final bpm in [startBpm, endBpm]) {
      if (bpm < 25 || bpm > 250) {
        throw ArgumentError.value(bpm, 'bpm', 'Erlaubt sind 25 bis 250.');
      }
    }
    final old = await _required(id);
    final current = CardioSession.fromJson(_map(old.workingCopy));
    if (current.deletedAtUtc != null) {
      throw StateError('Die Cardio-Einheit ist gelöscht.');
    }
    final updated = current.copyWith(
      recoveryStartBpm: () => startBpm,
      recoveryEndBpm: () => endBpm,
      updatedAtUtc: _roundToSecond(clock()),
    );
    final body = updated.toJson();
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: cardioSessionAggregateType,
      aggregateId: id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(old, body),
      createdAtUtc: clock().toUtc(),
    );
    _changed();
    return updated;
  }

  /// Löscht die Einheit lokal sofort aus der Liste; der Server folgt über Sync.
  Future<void> deleteSession(String id) async {
    final old = await _required(id);
    final current = CardioSession.fromJson(_map(old.workingCopy));
    if (current.deletedAtUtc != null) return;
    final now = _roundToSecond(clock());
    final body = current
        .copyWith(deletedAtUtc: () => now, updatedAtUtc: now)
        .toJson();
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: cardioSessionAggregateType,
      aggregateId: id,
      operation: LocalMutationOperation.delete,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(old, body),
      createdAtUtc: now,
    );
    _changed();
  }

  /// Laufender Entwurf; null ohne laufende Einheit oder bei unlesbarem Stand.
  Future<CardioDraft?> readDraft() async {
    final raw = await store.readSyncMetadata(cardioDraftMetadataKey);
    if (raw is! Map<String, dynamic>) return null;
    try {
      return CardioDraft.fromJson(raw);
    } on Object {
      return null;
    }
  }

  Future<void> writeDraft(CardioDraft draft) =>
      store.writeSyncMetadata(cardioDraftMetadataKey, draft.toJson());

  Future<void> clearDraft() => store.deleteSyncMetadata(cardioDraftMetadataKey);

  Future<LocalAggregateEnvelope<Object?>> _required(String id) async =>
      await store.readAggregate(cardioSessionAggregateType, id) ??
      (throw StateError('Die Cardio-Einheit ist nicht verfügbar.'));
}

LocalAggregateEnvelope<Object?> _pending(
  LocalAggregateEnvelope<Object?> prior,
  Object? value,
) => LocalAggregateEnvelope(
  aggregateId: prior.aggregateId,
  serverSnapshot: prior.serverSnapshot,
  workingCopy: value,
  serverVersion: prior.serverVersion,
  optimisticVersion: prior.optimisticVersion + 1,
  syncState: LocalSyncState.pending,
);

Map<String, dynamic> _map(Object? value) => value is Map<String, dynamic>
    ? value
    : throw const FormatException('Expected cardio object.');

DateTime _roundToSecond(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
