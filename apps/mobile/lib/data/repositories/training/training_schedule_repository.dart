import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_validation.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';

/// Lokaler Typ des Rhythmus in `LocalResources` (D3a).
const trainingScheduleAggregateType = 'training-schedule';

/// Liest und schreibt den Trainingsrhythmus. Jede Änderung überträgt den
/// vollständigen Stand; ungesendete Änderungen fasst die Outbox zu einem
/// wartenden Eintrag zusammen. Pläne, auf die der Rhythmus verweist, sendet
/// der Sync vorher (siehe `SyncPayloadCodec.referencedAggregateIds`).
class TrainingScheduleRepository {
  TrainingScheduleRepository({
    required this.store,
    required this._ids,
    required this._clock,
    required this._readAllPlans,
    required this._readWorkouts,
  });

  final LocalSyncStore store;
  final String Function() _ids;
  final DateTime Function() _clock;
  final Future<List<TrainingPlanModel>> Function() _readAllPlans;
  final Future<List<Workout>> Function() _readWorkouts;

  /// Heutiger lokaler Kalendertag nach der Repository-Uhr.
  LocalDay today() => LocalDay.of(_clock().toLocal());

  /// Der aktuelle Rhythmus; null, wenn keiner angelegt oder er gelöscht ist.
  Future<TrainingSchedule?> read() async => (await _current())?.$2;

  /// Vorschau mit allen Plänen (auch archivierten) und Trainings für heute.
  Future<TrainingScheduleProjection> readProjection() async {
    final schedule = await read();
    return TrainingScheduleProjection(
      schedule: schedule,
      plans: await _readAllPlans(),
      workouts: await _readWorkouts(),
      today: today(),
    );
  }

  /// Legt den Rhythmus an oder ändert Modus bzw. Slots. Eine Änderung setzt
  /// Gültig-ab auf heute und verwirft Verschiebungen und Ausnahmen. Ohne
  /// Änderung bleibt der Stand unverändert.
  Future<TrainingSchedule> saveRhythm({
    required TrainingScheduleMode mode,
    required List<TrainingScheduleSlot> slots,
    int todaySlotIndex = 0,
  }) async {
    final plans = await _readAllPlans();
    final message = validateScheduleSlots(mode, slots, {
      for (final plan in plans)
        if (!plan.isArchived) plan.planId,
    });
    if (message != null) {
      throw WorkoutValidationException({'slots': message});
    }
    final known = {for (final plan in plans) plan.planId};
    if (slots.any(
      (slot) => slot.planId != null && !known.contains(slot.planId),
    )) {
      throw const WorkoutValidationException({
        'slots': 'Der Rhythmus enthält einen unbekannten Plan.',
      });
    }
    if (mode == TrainingScheduleMode.cycle &&
        (todaySlotIndex < 0 || todaySlotIndex >= slots.length)) {
      throw ArgumentError.value(todaySlotIndex, 'todaySlotIndex');
    }

    final day = today();
    final current = await _current();
    if (current == null) {
      final schedule = TrainingSchedule.create(
        scheduleId: _ids(),
        mode: mode,
        slots: slots,
        today: day,
        todaySlotIndex: todaySlotIndex,
      );
      await _commit(schedule, null, LocalMutationOperation.create);
      return schedule;
    }
    final (row, old) = current;
    final next = old.withRhythm(
      mode: mode,
      slots: slots,
      today: day,
      todaySlotIndex: todaySlotIndex,
    );
    if (_sameRhythm(old, next, day)) return old;
    await _commit(next, row, LocalMutationOperation.update);
    return next;
  }

  /// Wendet eine Tagesaktion an. [training] stammt aus einer Vorschau dieses
  /// Repositorys; die Aktion muss dort zulässig sein.
  Future<TrainingSchedule> applyAction(
    ScheduledTraining training,
    ScheduleAction action,
  ) async {
    final current = await _current();
    if (current == null) throw StateError('Es gibt keinen Rhythmus.');
    final (row, _) = current;
    final projection = await readProjection();
    final next = projection.apply(training, action);
    await _commit(next, row, LocalMutationOperation.update);
    return next;
  }

  /// Löscht den Rhythmus. Lokal verschwindet er sofort; der Server folgt
  /// über Sync. Ein nie gesendeter Rhythmus wird ganz verworfen.
  Future<void> delete() async {
    final current = await _current();
    if (current == null) return;
    final (row, schedule) = current;
    final deleted = schedule.copyWith(
      deletedAtUtc: () => _roundToSecond(_clock()),
    );
    await _commit(deleted, row, LocalMutationOperation.delete);
  }

  /// Gleicher Modus, gleiche Slots und am heutigen Tag derselbe Slot.
  bool _sameRhythm(TrainingSchedule old, TrainingSchedule next, LocalDay day) {
    if (old.mode != next.mode || old.slots.length != next.slots.length) {
      return false;
    }
    for (var i = 0; i < old.slots.length; i++) {
      if (old.slots[i] != next.slots[i]) return false;
    }
    if (!old.isCycle) return true;
    // Ein nicht verschobener Anker ist gleich, wenn heute derselbe Slot gilt.
    return old.anchorDate == next.anchorDate;
  }

  Future<(LocalAggregateEnvelope<Object?>, TrainingSchedule)?>
  _current() async {
    for (final row in await store.readAggregates(
      trainingScheduleAggregateType,
    )) {
      final schedule = TrainingSchedule.fromJson(
        (row.workingCopy! as Map).cast<String, Object?>(),
      );
      if (schedule.deletedAtUtc == null) return (row, schedule);
    }
    return null;
  }

  Future<void> _commit(
    TrainingSchedule schedule,
    LocalAggregateEnvelope<Object?>? old,
    LocalMutationOperation operation,
  ) async {
    final body = schedule.toJson();
    final id = schedule.scheduleId;
    await store.commitMutation(
      mutationId: _ids(),
      aggregateType: trainingScheduleAggregateType,
      aggregateId: id,
      operation: operation,
      baseVersion: old == null ? 0 : old.serverVersion,
      body: body,
      envelope: old == null
          ? localEnvelope(aggregateId: id, workingCopy: body)
          : LocalAggregateEnvelope<Object?>(
              aggregateId: id,
              serverSnapshot: old.serverSnapshot,
              workingCopy: body,
              serverVersion: old.serverVersion,
              optimisticVersion: old.optimisticVersion + 1,
              syncState: LocalSyncState.pending,
            ),
      createdAtUtc: _clock().toUtc(),
    );
  }
}

DateTime _roundToSecond(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}
