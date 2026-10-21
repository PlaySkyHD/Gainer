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
/// Ergebnis einer Tagesaktion.
class ScheduleActionResult {
  const ScheduleActionResult.applied(TrainingSchedule this.schedule)
    : message = null;

  const ScheduleActionResult.notPossible()
    : schedule = null,
      message = notPossibleMessage;

  /// Nutzertext, wenn sich der Tag seit dem Öffnen geändert hat.
  static const notPossibleMessage =
      'Diese Aktion ist nicht mehr möglich. Der Tag hat sich inzwischen geändert.';

  /// Neuer Stand; null, wenn nichts geschrieben wurde.
  final TrainingSchedule? schedule;
  final String? message;

  bool get applied => schedule != null;
}

/// Liest und schreibt den Trainingsrhythmus. Jede Änderung überträgt den
/// vollständigen Stand; ungesendete Änderungen fasst die Outbox zu einem
/// wartenden Eintrag zusammen. Pläne, auf die der Rhythmus verweist, sendet
/// der Sync vorher (siehe `SyncPayloadCodec.referencedAggregateIds`).
///
/// Der Server kennt höchstens einen Rhythmus je Nutzer. Deshalb behält der
/// Rhythmus seine ID, solange lokal eine Zeile existiert, auch eine gelöschte
/// (Löschmarke): Ein neuer Rhythmus nach dem Löschen speichert dieselbe ID
/// mit der Version der Löschung als Basis.
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

  /// Nicht gelöschte Trainings; mit `from`/`to` nur die, die an diesen
  /// lokalen Tagen begonnen haben.
  final Future<List<Workout>> Function({LocalDay? from, LocalDay? to})
  _readWorkouts;

  /// Heutiger lokaler Kalendertag nach der Repository-Uhr.
  LocalDay today() => LocalDay.of(_clock().toLocal());

  /// Der aktuelle Rhythmus; null, wenn keiner angelegt oder er gelöscht ist.
  Future<TrainingSchedule?> read() async => (await _row())?.live;

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
  /// Gültig-ab auf heute und verwirft Verschiebungen und Ausnahmen. Ist der
  /// Rhythmus effektiv gleich (gleiche Slots, heute derselbe Slot), bleibt
  /// alles unverändert, auch Verschiebungen und Ausnahmen.
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
    final row = await _row();
    final live = row?.live;
    if (live != null &&
        live.hasSameRhythm(
          mode: mode,
          slots: slots,
          today: day,
          todaySlotIndex: todaySlotIndex,
        )) {
      return live;
    }
    // Nur ohne jede lokale Zeile entsteht eine neue ID.
    final schedule = TrainingSchedule.create(
      scheduleId: row?.envelope.aggregateId ?? _ids(),
      mode: mode,
      slots: slots,
      today: day,
      todaySlotIndex: todaySlotIndex,
    );
    return _commit(schedule, row?.envelope);
  }

  /// Wendet eine Tagesaktion an. Das Training wird im aktuellen Stand neu
  /// gesucht (gleicher Tag, Plan und Ursprungstag); fehlt es dort oder ist
  /// die Aktion nicht mehr zulässig, wird nichts geschrieben.
  Future<ScheduleActionResult> applyAction(
    ScheduledTraining training,
    ScheduleAction action,
  ) async {
    final row = await _row();
    final schedule = row?.live;
    if (row == null || schedule == null) {
      return const ScheduleActionResult.notPossible();
    }
    // Status und Aktionen hängen nur von den Trainings dieses Tages ab.
    final projection = TrainingScheduleProjection(
      schedule: schedule,
      plans: await _readAllPlans(),
      workouts: await _readWorkouts(from: training.date, to: training.date),
      today: today(),
    );
    final current = projection
        .day(training.date)
        .trainings
        .where(
          (candidate) =>
              candidate.planId == training.planId &&
              candidate.originDate == training.originDate,
        )
        .firstOrNull;
    if (current == null || !projection.actionsFor(current).contains(action)) {
      return const ScheduleActionResult.notPossible();
    }
    final saved = await _commit(
      projection.apply(current, action),
      row.envelope,
    );
    return ScheduleActionResult.applied(saved);
  }

  /// Löscht den Rhythmus. Lokal verschwindet er sofort; der Server folgt
  /// über Sync. Ein nie gesendeter Rhythmus wird ganz verworfen.
  Future<void> delete() async {
    final row = await _row();
    final schedule = row?.live;
    if (row == null || schedule == null) return;
    await _commit(
      schedule.copyWith(deletedAtUtc: () => _roundToSecond(_clock())),
      row.envelope,
      operation: LocalMutationOperation.delete,
    );
  }

  /// Die lokale Zeile des Rhythmus; eine lebende hat Vorrang vor einer
  /// Löschmarke.
  Future<_ScheduleRow?> _row() async {
    _ScheduleRow? deleted;
    for (final envelope in await store.readAggregates(
      trainingScheduleAggregateType,
    )) {
      final working = envelope.workingCopy;
      if (working is! Map || working['deletedAtUtc'] != null) {
        deleted ??= _ScheduleRow(envelope, null);
        continue;
      }
      return _ScheduleRow(
        envelope,
        TrainingSchedule.fromJson(working.cast<String, Object?>()),
      );
    }
    return deleted;
  }

  /// Schreibt den Stand. Ohne bisherige Zeile ist es ein Anlegen mit Basis 0,
  /// sonst eine Änderung auf Basis der bekannten Serverversion. Eine noch
  /// nicht gesendete Löschung fasst die Outbox mit dem neuen Stand zusammen.
  /// Vor dem Schreiben wird alter Verlauf verdichtet.
  Future<TrainingSchedule> _commit(
    TrainingSchedule schedule,
    LocalAggregateEnvelope<Object?>? old, {
    LocalMutationOperation? operation,
  }) async {
    final compacted = schedule.deletedAtUtc == null
        ? schedule.compacted(today())
        : schedule;
    final body = compacted.toJson();
    final id = compacted.scheduleId;
    await store.commitMutation(
      mutationId: _ids(),
      aggregateType: trainingScheduleAggregateType,
      aggregateId: id,
      operation:
          operation ??
          (old == null
              ? LocalMutationOperation.create
              : LocalMutationOperation.update),
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
    return compacted;
  }
}

class _ScheduleRow {
  _ScheduleRow(this.envelope, this.live);

  final LocalAggregateEnvelope<Object?> envelope;

  /// Null bei einer Löschmarke.
  final TrainingSchedule? live;
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
