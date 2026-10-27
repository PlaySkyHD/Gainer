import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/nutrition/water_intake.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_conflict_recovery.dart' show waterIntakeAggregateType;
import '../sync/local_sync_store.dart';

export '../sync/local_conflict_recovery.dart' show waterIntakeAggregateType;

/// Namensraum der Tages-IDs (UUID v8, SHA-256); fest, damit jedes Gerät
/// dieselbe ID für denselben Nutzer und Tag bildet.
const _waterDayNamespace = '6f1c2a9e-4b7d-4e2a-9c3f-2d8b5a7e1f40';

/// Wie oft eine Änderung neu gelesen und erneut versucht wird, wenn ein Pull
/// oder eine Bestätigung den Tag zwischen Lesen und Schreiben ändert.
const _maxCommitAttempts = 3;

/// Speichern der Wassermenge ist gescheitert; [message] ist für den Nutzer.
class WaterIntakeSaveException implements Exception {
  const WaterIntakeSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Wassermenge je lokalem Tag über die kontogebundene Outbox (D2, D3).
///
/// Jede Änderung sendet die neue Summe des Tages. Die ID ist je Nutzer und
/// Tag fest (UUID v8), damit zwei Geräte denselben Tag nie unter zwei IDs
/// anlegen. Änderungen laufen nacheinander; der Commit prüft, dass der
/// gelesene Stand noch gilt, sonst wird neu gelesen.
class WaterIntakeRepository {
  WaterIntakeRepository({
    required this.store,
    required this.ids,
    required this.clock,
  });

  final LocalSyncStore store;
  final String Function() ids;
  final DateTime Function() clock;

  /// Läuft nach dem Lesen und vor dem Commit; nur für Tests, die ein
  /// Wettrennen mit dem Sync nachstellen.
  @visibleForTesting
  Future<void> Function()? beforeCommitForTesting;

  Future<void> _queue = Future.value();

  /// Feste ID der Wassermenge von [localDate] für dieses Konto.
  String dayIdFor(String localDate) =>
      waterIntakeDayId(store.accountId, localDate);

  /// Getrunkene Menge in ml; 0 ohne gespeicherten Tag.
  Future<int> read(String localDate) async {
    _requireDate(localDate);
    final existing = await _readDay(localDate);
    return existing == null ? 0 : _amountOf(existing.workingCopy);
  }

  /// Zeile von [localDate]: die mit fester ID, sonst eine vom Server unter
  /// anderer ID gezogene (z. B. von einer älteren App-Version angelegt).
  Future<LocalAggregateEnvelope<Object?>?> _readDay(String localDate) async {
    final fixed = await store.readAggregate(
      waterIntakeAggregateType,
      dayIdFor(localDate),
    );
    if (fixed != null) return fixed;
    return (await store.readAggregates(waterIntakeAggregateType)).where((row) {
      final working = row.workingCopy;
      return working is Map && working['localDate'] == localDate;
    }).firstOrNull;
  }

  /// Addiert [addedMl] und liefert die neue Tagesmenge.
  Future<int> add(String localDate, int addedMl) => _serialized(
    () => _change(localDate, (current) {
      if (!WaterIntakeLimits.canAdd(current, addedMl)) {
        throw const NutritionValidationException({
          'amountMl': 'Mehr als 10.000 ml am Tag sind nicht möglich.',
        });
      }
      return current + addedMl;
    }),
  );

  /// Setzt die Tagesmenge auf [amountMl] (Korrektur, Rückgängig).
  Future<int> setAmount(String localDate, int amountMl) => _serialized(
    () => _change(localDate, (_) {
      if (!WaterIntakeLimits.isValidDaily(amountMl)) {
        throw const NutritionValidationException({
          'amountMl': 'Erlaubt sind 0 bis 10.000 ml.',
        });
      }
      return amountMl;
    }),
  );

  Future<int> _change(String localDate, int Function(int current) next) async {
    _requireDate(localDate);
    for (var attempt = 1; ; attempt++) {
      final existing = await _readDay(localDate);
      final current = existing == null ? 0 : _amountOf(existing.workingCopy);
      final total = next(current);
      if (existing != null && total == current) return current;
      await beforeCommitForTesting?.call();
      try {
        await _commit(
          existing?.aggregateId ?? dayIdFor(localDate),
          localDate,
          existing,
          total,
        );
        return total;
      } on LocalResourceChangedException {
        // Ein Pull oder eine Bestätigung kam dazwischen: neu lesen.
        if (attempt >= _maxCommitAttempts) {
          throw const WaterIntakeSaveException(
            'Die Wassermenge hat sich gerade beim Synchronisieren geändert. '
            'Bitte versuche es noch einmal.',
          );
        }
      } on LocalWritesFrozenException {
        throw const WaterIntakeSaveException(
          'Während der Geräteübergabe lässt sich nichts ändern. Schließe sie '
          'zuerst ab oder brich sie ab.',
        );
      }
    }
  }

  Future<void> _commit(
    String id,
    String localDate,
    LocalAggregateEnvelope<Object?>? existing,
    int total,
  ) {
    final now = clock().toUtc();
    final previous = existing?.workingCopy;
    final working = <String, Object?>{
      'localDate': localDate,
      'amountMl': total,
      'createdAtUtc':
          (previous is Map ? previous['createdAtUtc'] : null) ??
          now.toIso8601String(),
      'updatedAtUtc': now.toIso8601String(),
    };
    return store.commitMutation(
      MutationDraft(
        mutationId: ids(),
        aggregateType: waterIntakeAggregateType,
        aggregateId: id,
        operation: existing == null
            ? LocalMutationOperation.create
            : LocalMutationOperation.update,
        baseVersion: existing?.serverVersion,
        body: working,
        envelope: existing == null
            ? localEnvelope(aggregateId: id, workingCopy: working)
            : LocalAggregateEnvelope(
                aggregateId: existing.aggregateId,
                serverSnapshot: existing.serverSnapshot,
                workingCopy: working,
                serverVersion: existing.serverVersion,
                optimisticVersion: existing.optimisticVersion + 1,
                syncState: LocalSyncState.pending,
              ),
        // Gilt der gelesene Stand beim Commit nicht mehr, schlägt er fehl.
        // Ein neuer Tag erwartet zusätzlich, dass kein Pull den Servertag
        // desselben Datums unter anderer ID geschrieben hat.
        resourceExpectations: [
          LocalResourceExpectation(
            aggregateType: waterIntakeAggregateType,
            aggregateId: id,
            optimisticVersion: existing?.optimisticVersion,
            serverVersion: existing?.serverVersion,
          ),
          if (existing == null)
            LocalUniqueFieldExpectation(
              aggregateType: waterIntakeAggregateType,
              aggregateId: id,
              field: 'localDate',
              value: localDate,
            ),
        ],
        createdAtUtc: now,
      ),
    );
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static int _amountOf(Object? workingCopy) {
    final value = workingCopy is Map ? workingCopy['amountMl'] : null;
    return value is num ? value.toInt() : 0;
  }

  static void _requireDate(String localDate) {
    if (!isValidLocalDate(localDate)) {
      throw const NutritionValidationException({
        'localDate': 'Ungültiger Kalendertag.',
      });
    }
  }
}

/// Namensbasierte UUID v8 (RFC 9562) aus Konto und Tag: die ersten 16 Byte
/// des SHA-256 über Namensraum, Konto und Datum, mit Version 8 und Variante
/// RFC 4122. Dieselben Eingaben ergeben auf jedem Gerät dieselbe ID,
/// verschiedene Konten nie dieselbe.
String waterIntakeDayId(String accountId, String localDate) {
  final namespace = _uuidBytes(_waterDayNamespace);
  final name = utf8.encode('${accountId.toLowerCase()}:$localDate');
  final hash = sha256.convert([...namespace, ...name]).bytes.sublist(0, 16);
  hash[6] = (hash[6] & 0x0f) | 0x80;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  final hex = hash.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> _uuidBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
