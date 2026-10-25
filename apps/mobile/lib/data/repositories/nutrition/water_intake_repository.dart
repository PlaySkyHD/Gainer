import 'dart:async';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/nutrition/water_intake.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';

/// Lokaler Aggregattyp der Wassermenge eines Tages (Server: `WaterIntakeDay`).
const waterIntakeAggregateType = 'water-intake-day';

/// Wassermenge je lokalem Tag über die kontogebundene Outbox (D2).
///
/// Jede Änderung liest den aktuellen Stand und schreibt in einer Warteschlange,
/// damit zwei schnelle Tipps nicht denselben Stand lesen. Wartet für den Tag
/// keine Änderung, geht eine Addition als `addedMl` mit; sonst trägt der Body
/// nur die neue Summe, die beim Zusammenfassen in der Outbox richtig bleibt.
class WaterIntakeRepository {
  WaterIntakeRepository({
    required this.store,
    required this.ids,
    required this.clock,
  });

  final LocalSyncStore store;
  final String Function() ids;
  final DateTime Function() clock;

  Future<void> _queue = Future.value();

  /// Getrunkene Menge in ml; 0 ohne gespeicherten Tag.
  Future<int> read(String localDate) async {
    _requireDate(localDate);
    final existing = await _find(localDate);
    return existing == null ? 0 : _amountOf(existing.workingCopy);
  }

  /// Addiert [addedMl] und liefert die neue Tagesmenge.
  Future<int> add(String localDate, int addedMl) =>
      _serialized(() => _change(localDate, addedMl, add: true));

  /// Setzt die Tagesmenge auf [amountMl] (Korrektur, Rückgängig).
  Future<int> setAmount(String localDate, int amountMl) =>
      _serialized(() => _change(localDate, amountMl, add: false));

  Future<int> _change(String localDate, int amount, {required bool add}) async {
    _requireDate(localDate);
    final existing = await _find(localDate);
    final current = existing == null ? 0 : _amountOf(existing.workingCopy);
    if (add && !WaterIntakeLimits.canAdd(current, amount)) {
      throw const NutritionValidationException({
        'amountMl': 'Mehr als 10.000 ml am Tag sind nicht möglich.',
      });
    }
    final total = add ? current + amount : amount;
    if (!WaterIntakeLimits.isValidDaily(total)) {
      throw const NutritionValidationException({
        'amountMl': 'Erlaubt sind 0 bis 10.000 ml.',
      });
    }
    if (existing != null && total == current) return current;

    final now = clock().toUtc();
    final aggregateId = existing?.aggregateId ?? ids();
    final previous = existing?.workingCopy;
    final working = <String, Object?>{
      'localDate': localDate,
      'amountMl': total,
      'createdAtUtc':
          (previous is Map ? previous['createdAtUtc'] : null) ??
          now.toIso8601String(),
      'updatedAtUtc': now.toIso8601String(),
    };
    // Nur ohne wartende Änderung als Addition senden (D2).
    final sendsDelta =
        add && (existing == null || existing.syncState == LocalSyncState.clean);
    await store.commitMutation(
      mutationId: ids(),
      aggregateType: waterIntakeAggregateType,
      aggregateId: aggregateId,
      operation: existing == null
          ? LocalMutationOperation.create
          : LocalMutationOperation.update,
      baseVersion: existing?.serverVersion,
      body: {...working, if (sendsDelta) 'addedMl': amount},
      envelope: existing == null
          ? localEnvelope(aggregateId: aggregateId, workingCopy: working)
          : LocalAggregateEnvelope(
              aggregateId: existing.aggregateId,
              serverSnapshot: existing.serverSnapshot,
              workingCopy: working,
              serverVersion: existing.serverVersion,
              optimisticVersion: existing.optimisticVersion + 1,
              syncState: LocalSyncState.pending,
            ),
      createdAtUtc: now,
    );
    return total;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<LocalAggregateEnvelope<Object?>?> _find(String localDate) async {
    for (final row in await store.readAggregates(waterIntakeAggregateType)) {
      final working = row.workingCopy;
      if (working is Map && working['localDate'] == localDate) return row;
    }
    return null;
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
