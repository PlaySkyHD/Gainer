import 'training_plan_model.dart';
import 'workout_model.dart';

/// Lokaler Kalendertag ohne Uhrzeit. Rechnet mit Kalendertagen statt mit
/// 24-Stunden-Dauern, damit ein Sommerzeitwechsel keinen Tag verschiebt.
class LocalDay implements Comparable<LocalDay> {
  LocalDay(int year, int month, int day)
    : this._(DateTime.utc(year, month, day));

  LocalDay._(DateTime utcMidnight)
    : year = utcMidnight.year,
      month = utcMidnight.month,
      day = utcMidnight.day;

  /// Kalendertag eines Zeitpunkts in der Zeitzone, in der er vorliegt.
  /// Für UTC-Zeitpunkte vorher `toLocal()` aufrufen.
  factory LocalDay.of(DateTime moment) =>
      LocalDay(moment.year, moment.month, moment.day);

  /// Liest „YYYY-MM-DD“.
  factory LocalDay.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('Expected a date as YYYY-MM-DD.', value);
    }
    final day = LocalDay(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (day.toIso() != value) {
      throw FormatException('Not a calendar date.', value);
    }
    return day;
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// 1 = Montag … 7 = Sonntag.
  int get weekday => _utc.weekday;

  LocalDay addDays(int days) => LocalDay(year, month, day + days);

  /// Tage von diesem Tag bis [other]; negativ, wenn [other] davor liegt.
  int daysUntil(LocalDay other) => other._utc.difference(_utc).inDays;

  bool isBefore(LocalDay other) => compareTo(other) < 0;

  bool isAfter(LocalDay other) => compareTo(other) > 0;

  /// „YYYY-MM-DD“, wie im Sync-Vertrag.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Lokale Mitternacht dieses Tages, z. B. für Anzeigeformate.
  DateTime toDateTime() => DateTime(year, month, day);

  @override
  int compareTo(LocalDay other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is LocalDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// Lokaler Tag eines UTC-Zeitpunkts in der Gerätezeitzone.
LocalDay localDayOfUtc(DateTime utc) => LocalDay.of(utc.toLocal());

/// Modus des Rhythmus.
enum TrainingScheduleMode {
  /// Geordnete Folge aus Plänen und Ruhetagen, 1 bis 28 Slots.
  cycle('cycle'),

  /// Sieben Slots von Montag bis Sonntag.
  weekly('weekly');

  const TrainingScheduleMode(this.wireName);

  final String wireName;

  static TrainingScheduleMode fromWire(Object? value) => values.firstWhere(
    (mode) => mode.wireName == value,
    orElse: () => throw FormatException('Unknown schedule mode.', value),
  );
}

/// Ein Tag des Rhythmus: ein Plan oder ein Ruhetag (`planId == null`).
class TrainingScheduleSlot {
  const TrainingScheduleSlot({this.planId});

  const TrainingScheduleSlot.rest() : planId = null;

  factory TrainingScheduleSlot.fromJson(Map<String, Object?> json) =>
      TrainingScheduleSlot(planId: json['planId'] as String?);

  final String? planId;

  bool get isRest => planId == null;

  Map<String, Object?> toJson() => {'planId': planId};

  @override
  bool operator ==(Object other) =>
      other is TrainingScheduleSlot && other.planId == planId;

  @override
  int get hashCode => planId.hashCode;
}

/// „Rhythmus verschieben“: ab [fromDate] rückt der Zyklus um [days] Tage nach.
class TrainingScheduleShift {
  const TrainingScheduleShift({required this.fromDate, required this.days});

  factory TrainingScheduleShift.fromJson(Map<String, Object?> json) =>
      TrainingScheduleShift(
        fromDate: LocalDay.parse(json['fromDate']! as String),
        days: (json['days']! as num).toInt(),
      );

  final LocalDay fromDate;
  final int days;

  /// Die frei werdenden Tage gelten als pausiert.
  bool pauses(LocalDay date) =>
      !date.isBefore(fromDate) && date.isBefore(fromDate.addDays(days));

  Map<String, Object?> toJson() => {'fromDate': fromDate.toIso(), 'days': days};

  @override
  bool operator ==(Object other) =>
      other is TrainingScheduleShift &&
      other.fromDate == fromDate &&
      other.days == days;

  @override
  int get hashCode => Object.hash(fromDate, days);
}

/// Verschiebung (`movedToDate`) oder Überspringen (`movedToDate == null`)
/// eines einzelnen Trainings. Sie gilt nur, solange an [date] noch [planId]
/// vorgesehen ist.
class TrainingScheduleException {
  const TrainingScheduleException({
    required this.date,
    required this.planId,
    this.movedToDate,
  });

  factory TrainingScheduleException.fromJson(Map<String, Object?> json) {
    final moved = json['movedToDate'] as String?;
    return TrainingScheduleException(
      date: LocalDay.parse(json['date']! as String),
      planId: json['planId']! as String,
      movedToDate: moved == null ? null : LocalDay.parse(moved),
    );
  }

  final LocalDay date;
  final String planId;
  final LocalDay? movedToDate;

  bool get isSkip => movedToDate == null;

  Map<String, Object?> toJson() => {
    'date': date.toIso(),
    'planId': planId,
    'movedToDate': movedToDate?.toIso(),
  };

  @override
  bool operator ==(Object other) =>
      other is TrainingScheduleException &&
      other.date == date &&
      other.planId == planId &&
      other.movedToDate == movedToDate;

  @override
  int get hashCode => Object.hash(date, planId, movedToDate);
}

/// Höchstzahl der Slots im Zyklus.
const maxCycleSlots = 28;

/// Höchstzahl an Tagen einer einzelnen Rhythmus-Verschiebung (Vertrag).
const maxShiftDays = 31;

/// Wie viele Tage ein verpasstes Training höchstens zurückliegen darf, um es
/// nachzuholen.
const catchUpWindowDays = 7;

/// Der Trainingsrhythmus eines Nutzers. Die lokale Arbeitskopie hat die Form
/// des Server-Snapshots (D3a); `deletedAtUtc` gibt es nur lokal, solange eine
/// Löschung noch nicht bestätigt ist.
class TrainingSchedule {
  TrainingSchedule({
    required this.scheduleId,
    required this.mode,
    required this.validFrom,
    required List<TrainingScheduleSlot> slots,
    this.anchorDate,
    List<TrainingScheduleShift> shifts = const [],
    List<TrainingScheduleException> exceptions = const [],
    this.updatedAtUtc,
    this.deletedAtUtc,
  }) : slots = List.unmodifiable(slots),
       shifts = List.unmodifiable(shifts),
       exceptions = List.unmodifiable(exceptions);

  factory TrainingSchedule.fromJson(Map<String, Object?> json) {
    final anchor = json['anchorDate'] as String?;
    final updated = json['updatedAtUtc'] as String?;
    final deleted = json['deletedAtUtc'] as String?;
    List<Map<String, Object?>> list(String key) => [
      for (final entry in (json[key] as List<Object?>? ?? const []))
        (entry! as Map).cast<String, Object?>(),
    ];
    return TrainingSchedule(
      scheduleId: json['scheduleId']! as String,
      mode: TrainingScheduleMode.fromWire(json['mode']),
      anchorDate: anchor == null ? null : LocalDay.parse(anchor),
      validFrom: LocalDay.parse(json['validFrom']! as String),
      slots: [
        for (final slot in list('slots')) TrainingScheduleSlot.fromJson(slot),
      ],
      shifts: [
        for (final shift in list('shifts'))
          TrainingScheduleShift.fromJson(shift),
      ],
      exceptions: [
        for (final exception in list('exceptions'))
          TrainingScheduleException.fromJson(exception),
      ],
      updatedAtUtc: updated == null ? null : DateTime.parse(updated),
      deletedAtUtc: deleted == null ? null : DateTime.parse(deleted),
    );
  }

  /// Neuer Rhythmus ab [today]. Im Zyklus liegt [todaySlotIndex] auf heute.
  factory TrainingSchedule.create({
    required String scheduleId,
    required TrainingScheduleMode mode,
    required List<TrainingScheduleSlot> slots,
    required LocalDay today,
    int todaySlotIndex = 0,
  }) => TrainingSchedule(
    scheduleId: scheduleId,
    mode: mode,
    validFrom: today,
    slots: slots,
    anchorDate: mode == TrainingScheduleMode.cycle
        ? today.addDays(-todaySlotIndex)
        : null,
  );

  final String scheduleId;
  final TrainingScheduleMode mode;

  /// Nur im Zyklus: Tag, an dem Slot 0 ohne Verschiebungen liegt.
  final LocalDay? anchorDate;

  /// Tag der letzten Änderung an Modus oder Slots.
  final LocalDay validFrom;
  final List<TrainingScheduleSlot> slots;
  final List<TrainingScheduleShift> shifts;
  final List<TrainingScheduleException> exceptions;
  final DateTime? updatedAtUtc;
  final DateTime? deletedAtUtc;

  bool get isCycle => mode == TrainingScheduleMode.cycle;

  Map<String, Object?> toJson() => {
    'scheduleId': scheduleId,
    'mode': mode.wireName,
    'anchorDate': isCycle ? anchorDate?.toIso() : null,
    'validFrom': validFrom.toIso(),
    'slots': [for (final slot in slots) slot.toJson()],
    'shifts': [for (final shift in shifts) shift.toJson()],
    'exceptions': [for (final exception in exceptions) exception.toJson()],
    if (updatedAtUtc case final updated?)
      'updatedAtUtc': updated.toUtc().toIso8601String(),
    if (deletedAtUtc case final deleted?)
      'deletedAtUtc': deleted.toUtc().toIso8601String(),
  };

  TrainingSchedule copyWith({
    TrainingScheduleMode? mode,
    LocalDay? anchorDate,
    LocalDay? validFrom,
    List<TrainingScheduleSlot>? slots,
    List<TrainingScheduleShift>? shifts,
    List<TrainingScheduleException>? exceptions,
    DateTime? Function()? deletedAtUtc,
  }) => TrainingSchedule(
    scheduleId: scheduleId,
    mode: mode ?? this.mode,
    anchorDate: anchorDate ?? this.anchorDate,
    validFrom: validFrom ?? this.validFrom,
    slots: slots ?? this.slots,
    shifts: shifts ?? this.shifts,
    exceptions: exceptions ?? this.exceptions,
    updatedAtUtc: updatedAtUtc,
    deletedAtUtc: deletedAtUtc == null ? this.deletedAtUtc : deletedAtUtc(),
  );

  // Rhythmus ändern

  /// Neuer Modus bzw. neue Slots ab [today]. Verschiebungen und Ausnahmen
  /// beziehen sich auf den alten Rhythmus und entfallen.
  TrainingSchedule withRhythm({
    required TrainingScheduleMode mode,
    required List<TrainingScheduleSlot> slots,
    required LocalDay today,
    int todaySlotIndex = 0,
  }) => TrainingSchedule(
    scheduleId: scheduleId,
    mode: mode,
    validFrom: today,
    slots: slots,
    anchorDate: mode == TrainingScheduleMode.cycle
        ? today.addDays(-todaySlotIndex)
        : null,
    updatedAtUtc: updatedAtUtc,
  );

  /// Index des Slots, der im Zyklus heute gilt; null bei festen Tagen,
  /// pausierten Tagen oder vor dem Gültig-ab-Datum.
  int? cycleSlotIndexOn(LocalDay date) {
    final raw = _rawSlot(date);
    return raw is _SlotAt && isCycle ? raw.index : null;
  }

  /// Slot, der im Zyklus für [today] gilt, wie ihn der Editor als „Heute
  /// ist“ zeigt. An einem pausierten Tag ist es der Slot vor dem nächsten
  /// nicht pausierten Tag. Null bei festen Tagen oder ohne Slots.
  int? effectiveCycleIndex(LocalDay today) {
    if (!isCycle || slots.isEmpty) return null;
    for (var offset = 0; offset <= maxShiftDays * 2; offset++) {
      final index = cycleSlotIndexOn(today.addDays(offset));
      if (index != null) return (index - offset) % slots.length;
    }
    return null;
  }

  /// Gleicher Modus, gleiche Slots und im Zyklus heute derselbe Slot wie bei
  /// [todaySlotIndex]. Dann ändert ein Speichern den Rhythmus nicht.
  bool hasSameRhythm({
    required TrainingScheduleMode mode,
    required List<TrainingScheduleSlot> slots,
    required LocalDay today,
    int todaySlotIndex = 0,
  }) {
    if (mode != this.mode || slots.length != this.slots.length) return false;
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] != this.slots[i]) return false;
    }
    return !isCycle || effectiveCycleIndex(today) == todaySlotIndex;
  }

  /// Wie viele Tage die Vergangenheit beim Verdichten mindestens unverändert
  /// bleibt (gut 13 Monate).
  static const compactionKeepDays = 400;

  /// Entfernt Verlauf, der für die Vorschau ab `today - keepDays` keine Rolle
  /// mehr spielt, damit Verschiebungen und Ausnahmen nicht unbegrenzt
  /// wachsen (Server-Obergrenze 1000):
  /// - Ausnahmen, deren Tag und Ziel vor der Grenze liegen, entfallen.
  /// - Verschiebungen, die vor der Grenze enden, gehen in den Anker ein.
  /// - Gültig-ab rückt bis zur Grenze vor.
  /// Die Vorschau ab der Grenze bleibt identisch.
  TrainingSchedule compacted(
    LocalDay today, {
    int keepDays = compactionKeepDays,
  }) {
    final cutoff = today.addDays(-keepDays);
    final kept = [
      for (final exception in exceptions)
        if (!exception.date.isBefore(cutoff) ||
            (exception.movedToDate != null &&
                !exception.movedToDate!.isBefore(cutoff)))
          exception,
    ];
    // Eine behaltene Ausnahme gilt nur, solange ihr Tag noch vorgesehen ist;
    // ihr Tag muss deshalb im Gültigkeitsbereich bleiben.
    var boundary = cutoff;
    for (final exception in kept) {
      if (exception.date.isBefore(boundary)) boundary = exception.date;
    }
    if (!validFrom.isBefore(boundary)) {
      if (kept.length == exceptions.length) return this;
      return copyWith(exceptions: kept);
    }
    var anchor = anchorDate;
    final keptShifts = <TrainingScheduleShift>[];
    for (final shift in shifts) {
      if (anchor != null &&
          !shift.fromDate.addDays(shift.days).isAfter(boundary)) {
        anchor = anchor.addDays(shift.days);
      } else {
        keptShifts.add(shift);
      }
    }
    return TrainingSchedule(
      scheduleId: scheduleId,
      mode: mode,
      anchorDate: anchor,
      validFrom: boundary,
      slots: slots,
      shifts: keptShifts,
      exceptions: kept,
      updatedAtUtc: updatedAtUtc,
      deletedAtUtc: deletedAtUtc,
    );
  }

  // Tagesaktionen (reine Funktionen, liefern einen neuen Stand)

  /// Verschiebt den Zyklus ab [from] um [days] Tage. Gibt es schon eine
  /// Verschiebung ab diesem Tag, wächst sie.
  TrainingSchedule shiftRhythm(LocalDay from, int days) {
    if (!isCycle) {
      throw StateError('Nur ein Zyklus lässt sich verschieben.');
    }
    if (days < 1) throw ArgumentError.value(days, 'days');
    final existing = shifts
        .where((shift) => shift.fromDate == from)
        .firstOrNull;
    final total = (existing?.days ?? 0) + days;
    if (total > maxShiftDays) {
      throw StateError('Der Rhythmus lässt sich nicht weiter verschieben.');
    }
    final next = [
      for (final shift in shifts)
        if (shift.fromDate != from) shift,
      TrainingScheduleShift(fromDate: from, days: total),
    ]..sort((a, b) => a.fromDate.compareTo(b.fromDate));
    return copyWith(shifts: next);
  }

  /// Verschiebt nur das Training [planId], das an [date] vorgesehen ist,
  /// auf [target].
  TrainingSchedule moveSingle(LocalDay date, String planId, LocalDay target) =>
      _withException(
        TrainingScheduleException(
          date: date,
          planId: planId,
          movedToDate: target,
        ),
      );

  /// Überspringt das Training [planId], das an [date] vorgesehen ist.
  TrainingSchedule skip(LocalDay date, String planId) =>
      _withException(TrainingScheduleException(date: date, planId: planId));

  /// Hebt die Verschiebung oder das Überspringen von [planId] an [date] auf.
  TrainingSchedule undo(LocalDay date, String planId) => copyWith(
    exceptions: [
      for (final exception in exceptions)
        if (exception.date != date || exception.planId != planId) exception,
    ],
  );

  /// Verpasstes Training von [missedDate] nur für sich auf heute legen.
  TrainingSchedule catchUpToday(
    LocalDay missedDate,
    String planId,
    LocalDay today,
  ) => moveSingle(missedDate, planId, today);

  /// Zyklus ab [missedDate] so verschieben, dass das verpasste Training heute
  /// liegt.
  TrainingSchedule continueFromToday(LocalDay missedDate, LocalDay today) =>
      shiftRhythm(missedDate, missedDate.daysUntil(today));

  TrainingSchedule _withException(TrainingScheduleException next) => copyWith(
    exceptions: [
      for (final exception in exceptions)
        if (exception.date != next.date || exception.planId != next.planId)
          exception,
      next,
    ],
  );

  // Vorschau

  _RawSlot _rawSlot(LocalDay date) {
    if (date.isBefore(validFrom) || slots.isEmpty) return const _NoSlot();
    if (!isCycle) {
      if (slots.length != 7) return const _NoSlot();
      return _SlotAt(date.weekday - 1);
    }
    final anchor = anchorDate;
    if (anchor == null) return const _NoSlot();
    var shifted = 0;
    for (final shift in shifts) {
      if (shift.fromDate.isAfter(date)) continue;
      if (shift.pauses(date)) return const _PausedSlot();
      shifted += shift.days;
    }
    // `%` ist in Dart bei positivem Divisor nie negativ, auch vor dem Anker.
    return _SlotAt((anchor.daysUntil(date) - shifted) % slots.length);
  }
}

sealed class _RawSlot {
  const _RawSlot();
}

class _NoSlot extends _RawSlot {
  const _NoSlot();
}

class _PausedSlot extends _RawSlot {
  const _PausedSlot();
}

class _SlotAt extends _RawSlot {
  const _SlotAt(this.index);
  final int index;
}

/// Was der Rhythmus selbst für einen Tag vorsieht, vor Ausnahmen.
enum ScheduleBaseKind {
  /// Kein Rhythmus oder vor dem Gültig-ab-Datum.
  none,

  /// Ruhetag, auch für einen Slot mit archiviertem Plan.
  rest,

  /// Durch „Rhythmus verschieben“ frei gewordener Tag.
  paused,

  /// Ein aktiver Plan ist vorgesehen.
  training,
}

/// Status eines geplanten Trainings an seinem Tag.
enum ScheduledTrainingStatus {
  /// Heute oder künftig, noch nicht erledigt.
  planned,

  /// Ein beendetes Training aus diesem Plan wurde an dem Tag gestartet.
  done,

  /// Vergangen, an dem Tag wurde kein Training beendet.
  missed,

  /// Vergangen, an dem Tag wurde ein anderes Training beendet.
  insteadOf,

  /// Nur dieses Training liegt auf einem anderen Tag.
  moved,

  /// Dieses Training fällt weg.
  skipped,
}

/// Ein geplantes Training an einem Tag.
class ScheduledTraining {
  const ScheduledTraining({
    required this.planId,
    required this.planName,
    required this.date,
    required this.originDate,
    required this.status,
    this.movedToDate,
    this.completedBy = const [],
    this.instead = const [],
  });

  final String planId;
  final String planName;

  /// Tag, an dem das Training angezeigt wird.
  final LocalDay date;

  /// Tag, an dem der Rhythmus es vorsieht. Weicht bei verschobenen
  /// (hineingeschobenen) Trainings von [date] ab.
  final LocalDay originDate;
  final ScheduledTrainingStatus status;

  /// Ziel einer Verschiebung bei Status [ScheduledTrainingStatus.moved].
  final LocalDay? movedToDate;

  /// Beendete Trainings aus diesem Plan an diesem Tag.
  final List<Workout> completedBy;

  /// Bei [ScheduledTrainingStatus.insteadOf]: die stattdessen beendeten Trainings.
  final List<Workout> instead;

  /// Durch eine Ausnahme von einem anderen Tag hierher verschoben.
  bool get isMovedIn => originDate != date;

  /// Kann der Nutzer es noch an [date] trainieren (geplant, nicht erledigt)?
  bool get isOpen => status == ScheduledTrainingStatus.planned;
}

/// Ein Tag der Vorschau mit allen geplanten Trainings.
class ScheduleDay {
  const ScheduleDay({
    required this.date,
    required this.baseKind,
    required this.trainings,
    this.slotIndex,
    this.archivedPlanId,
  });

  final LocalDay date;
  final ScheduleBaseKind baseKind;

  /// Slot des Rhythmus an diesem Tag; null ohne Rhythmus und an pausierten Tagen.
  final int? slotIndex;

  /// Plan im Slot, der archiviert ist und deshalb als Ruhetag zählt.
  final String? archivedPlanId;

  /// Das vom Rhythmus vorgesehene Training (auch verschoben oder übersprungen)
  /// und alle hierher verschobenen Trainings.
  final List<ScheduledTraining> trainings;

  /// Trainings, die an diesem Tag tatsächlich anstehen oder erledigt wurden.
  List<ScheduledTraining> get effective => [
    for (final training in trainings)
      if (training.status != ScheduledTrainingStatus.moved &&
          training.status != ScheduledTrainingStatus.skipped)
        training,
  ];

  /// Kein Training steht an: Ruhetag, pausiert oder alles verschoben.
  bool get isFree => effective.isEmpty;
}

/// Berechnet die Vorschau eines Rhythmus. Rein und deterministisch: Pläne,
/// Trainings und der heutige Tag werden übergeben.
class TrainingScheduleProjection {
  TrainingScheduleProjection({
    required this.schedule,
    required List<TrainingPlanModel> plans,
    required List<Workout> workouts,
    required this.today,
    LocalDay Function(DateTime utc) localDayOf = localDayOfUtc,
  }) : _plans = {for (final plan in plans) plan.planId: plan},
       _finishedByDay = _groupFinished(workouts, localDayOf);

  /// Null ohne Rhythmus; dann ist jeder Tag [ScheduleBaseKind.none].
  final TrainingSchedule? schedule;
  final LocalDay today;
  final Map<String, TrainingPlanModel> _plans;
  final Map<LocalDay, List<Workout>> _finishedByDay;

  static Map<LocalDay, List<Workout>> _groupFinished(
    List<Workout> workouts,
    LocalDay Function(DateTime utc) localDayOf,
  ) {
    final byDay = <LocalDay, List<Workout>>{};
    for (final workout in workouts) {
      if (workout.endedAtUtc == null || workout.deletedAtUtc != null) continue;
      byDay
          .putIfAbsent(localDayOf(workout.startedAtUtc), () => [])
          .add(workout);
    }
    return byDay;
  }

  TrainingPlanModel? plan(String planId) => _plans[planId];

  /// Wurde an [date] ein (nicht gelöschtes) Krafttraining gestartet und
  /// beendet? Gilt auch ohne Rhythmus.
  bool hasFinishedOn(LocalDay date) =>
      _finishedByDay[date]?.isNotEmpty ?? false;

  String planName(String planId) => _plans[planId]?.name ?? 'Plan';

  bool _isActivePlan(String? planId) {
    if (planId == null) return false;
    final plan = _plans[planId];
    return plan != null && !plan.isArchived;
  }

  /// Aktiver Plan, den der Rhythmus an [date] ohne Ausnahmen vorsieht.
  String? basePlanOn(LocalDay date) {
    final active = schedule;
    if (active == null) return null;
    final raw = active._rawSlot(date);
    if (raw is! _SlotAt) return null;
    final planId = active.slots[raw.index].planId;
    return _isActivePlan(planId) ? planId : null;
  }

  /// Gilt die Ausnahme noch, d. h. ist an ihrem Tag noch derselbe Plan vorgesehen?
  bool isEffective(TrainingScheduleException exception) =>
      basePlanOn(exception.date) == exception.planId;

  ScheduleDay day(LocalDay date) {
    final active = schedule;
    if (active == null) {
      return ScheduleDay(
        date: date,
        baseKind: ScheduleBaseKind.none,
        trainings: const [],
      );
    }
    final raw = active._rawSlot(date);
    final ScheduleBaseKind kind;
    int? slotIndex;
    String? archived;
    String? basePlan;
    switch (raw) {
      case _NoSlot():
        kind = ScheduleBaseKind.none;
      case _PausedSlot():
        kind = ScheduleBaseKind.paused;
      case _SlotAt(:final index):
        slotIndex = index;
        final planId = active.slots[index].planId;
        if (_isActivePlan(planId)) {
          kind = ScheduleBaseKind.training;
          basePlan = planId;
        } else {
          kind = ScheduleBaseKind.rest;
          if (planId != null) archived = planId;
        }
    }

    final finished = _finishedByDay[date] ?? const <Workout>[];
    final entries = <(String, LocalDay, TrainingScheduleException?)>[];
    if (basePlan != null) {
      final exception = active.exceptions
          .where((e) => e.date == date && e.planId == basePlan)
          .firstOrNull;
      entries.add((basePlan, date, exception));
    }
    for (final exception in active.exceptions) {
      if (exception.movedToDate == date &&
          exception.date != date &&
          isEffective(exception)) {
        entries.add((exception.planId, exception.date, null));
      }
    }

    // Trainings aus geplanten Plänen zählen nicht als „stattdessen“.
    final scheduledPlans = {
      for (final (planId, _, exception) in entries)
        if (exception == null) planId,
    };
    final others = [
      for (final workout in finished)
        if (!scheduledPlans.contains(workout.sourcePlanId)) workout,
    ];

    final trainings = [
      for (final (planId, origin, exception) in entries)
        _training(planId, date, origin, exception, finished, others),
    ];
    return ScheduleDay(
      date: date,
      baseKind: kind,
      slotIndex: slotIndex,
      archivedPlanId: archived,
      trainings: trainings,
    );
  }

  ScheduledTraining _training(
    String planId,
    LocalDay date,
    LocalDay origin,
    TrainingScheduleException? exception,
    List<Workout> finished,
    List<Workout> others,
  ) {
    final name = planName(planId);
    if (exception != null) {
      return ScheduledTraining(
        planId: planId,
        planName: name,
        date: date,
        originDate: origin,
        status: exception.isSkip
            ? ScheduledTrainingStatus.skipped
            : ScheduledTrainingStatus.moved,
        movedToDate: exception.movedToDate,
      );
    }
    final completed = [
      for (final workout in finished)
        if (workout.sourcePlanId == planId) workout,
    ];
    final ScheduledTrainingStatus status;
    if (completed.isNotEmpty) {
      status = ScheduledTrainingStatus.done;
    } else if (!date.isBefore(today)) {
      status = ScheduledTrainingStatus.planned;
    } else if (others.isNotEmpty) {
      status = ScheduledTrainingStatus.insteadOf;
    } else {
      status = ScheduledTrainingStatus.missed;
    }
    return ScheduledTraining(
      planId: planId,
      planName: name,
      date: date,
      originDate: origin,
      status: status,
      completedBy: completed,
      instead: status == ScheduledTrainingStatus.insteadOf ? others : const [],
    );
  }

  /// Tage von [from] bis einschließlich [to].
  List<ScheduleDay> days(LocalDay from, LocalDay to) => [
    for (var date = from; !date.isAfter(to); date = date.addDays(1)) day(date),
  ];

  /// Nächstes offenes Training nach [after] innerhalb von [horizonDays] Tagen.
  ScheduledTraining? nextPlannedAfter(LocalDay after, {int horizonDays = 60}) {
    if (schedule == null) return null;
    for (var offset = 1; offset <= horizonDays; offset++) {
      final open = day(after.addDays(offset)).trainings.where((t) => t.isOpen);
      if (open.isNotEmpty) return open.first;
    }
    return null;
  }

  /// Zulässige Tagesaktionen für [training] (D7, `training-schedule`).
  List<ScheduleAction> actionsFor(ScheduledTraining training) {
    final active = schedule;
    if (active == null) return const [];
    final date = training.date;
    final actions = <ScheduleAction>[];
    switch (training.status) {
      case ScheduledTrainingStatus.planned:
        if (date.isBefore(today)) break;
        if (active.isCycle && !training.isMovedIn) {
          actions
            ..add(ScheduleAction.shiftRhythm(1))
            ..add(ScheduleAction.shiftRhythm(2));
        }
        actions
          ..add(ScheduleAction.moveSingle(date.addDays(1)))
          ..add(ScheduleAction.moveSingle(date.addDays(2)))
          ..add(const ScheduleAction.skip());
        if (training.isMovedIn) actions.add(const ScheduleAction.undo());
      case ScheduledTrainingStatus.missed:
        if (date.daysUntil(today) > catchUpWindowDays) break;
        actions.add(const ScheduleAction.catchUpToday());
        if (active.isCycle && !training.isMovedIn) {
          actions.add(const ScheduleAction.continueFromToday());
        }
        if (training.isMovedIn) actions.add(const ScheduleAction.undo());
      case ScheduledTrainingStatus.skipped:
        if (!date.isBefore(today)) actions.add(const ScheduleAction.undo());
      case ScheduledTrainingStatus.moved:
        final target = training.movedToDate;
        if (target != null && !target.isBefore(today)) {
          actions.add(const ScheduleAction.undo());
        }
      case ScheduledTrainingStatus.done:
      case ScheduledTrainingStatus.insteadOf:
        break;
    }
    return actions;
  }

  /// Wendet eine zulässige Aktion an und liefert den neuen Stand.
  TrainingSchedule apply(ScheduledTraining training, ScheduleAction action) {
    final active = schedule;
    if (active == null) throw StateError('Es gibt keinen Rhythmus.');
    if (!actionsFor(training).contains(action)) {
      throw StateError('Diese Aktion ist hier nicht möglich.');
    }
    return switch (action.kind) {
      ScheduleActionKind.shiftRhythm => active.shiftRhythm(
        training.date,
        action.days!,
      ),
      ScheduleActionKind.moveSingle => active.moveSingle(
        training.originDate,
        training.planId,
        action.targetDate!,
      ),
      ScheduleActionKind.skip => active.skip(
        training.originDate,
        training.planId,
      ),
      ScheduleActionKind.catchUpToday => active.catchUpToday(
        training.originDate,
        training.planId,
        today,
      ),
      ScheduleActionKind.continueFromToday => active.continueFromToday(
        training.date,
        today,
      ),
      ScheduleActionKind.undo => active.undo(
        training.originDate,
        training.planId,
      ),
    };
  }

  /// Ausnahmen nach [from], die durch „Rhythmus verschieben“ wirkungslos würden.
  int exceptionsVoidedByShift(LocalDay from, int days) {
    final active = schedule;
    if (active == null || !active.isCycle) return 0;
    final shifted = TrainingScheduleProjection._derived(
      active.shiftRhythm(from, days),
      this,
    );
    return active.exceptions
        .where(
          (e) =>
              !e.date.isBefore(from) &&
              isEffective(e) &&
              !shifted.isEffective(e),
        )
        .length;
  }

  TrainingScheduleProjection._derived(
    TrainingSchedule this.schedule,
    TrainingScheduleProjection source,
  ) : today = source.today,
      _plans = source._plans,
      _finishedByDay = source._finishedByDay;
}

enum ScheduleActionKind {
  /// Nur Zyklus: dieses und alle folgenden Trainings um [ScheduleAction.days].
  shiftRhythm,

  /// Nur dieses Training auf [ScheduleAction.targetDate].
  moveSingle,
  skip,

  /// Verpasstes Training nur für sich auf heute.
  catchUpToday,

  /// Nur Zyklus: Rhythmus ab dem verpassten Tag so verschieben, dass es heute liegt.
  continueFromToday,

  /// Verschiebung oder Überspringen aufheben.
  undo,
}

/// Eine Tagesaktion für ein geplantes Training.
class ScheduleAction {
  const ScheduleAction.shiftRhythm(int this.days)
    : kind = ScheduleActionKind.shiftRhythm,
      targetDate = null;

  const ScheduleAction.moveSingle(LocalDay this.targetDate)
    : kind = ScheduleActionKind.moveSingle,
      days = null;

  const ScheduleAction.skip()
    : kind = ScheduleActionKind.skip,
      days = null,
      targetDate = null;

  const ScheduleAction.catchUpToday()
    : kind = ScheduleActionKind.catchUpToday,
      days = null,
      targetDate = null;

  const ScheduleAction.continueFromToday()
    : kind = ScheduleActionKind.continueFromToday,
      days = null,
      targetDate = null;

  const ScheduleAction.undo()
    : kind = ScheduleActionKind.undo,
      days = null,
      targetDate = null;

  final ScheduleActionKind kind;
  final int? days;
  final LocalDay? targetDate;

  @override
  bool operator ==(Object other) =>
      other is ScheduleAction &&
      other.kind == kind &&
      other.days == days &&
      other.targetDate == targetDate;

  @override
  int get hashCode => Object.hash(kind, days, targetDate);

  @override
  String toString() => 'ScheduleAction($kind, $days, $targetDate)';
}

/// Prüft die Slot-Regeln (Spec „Rhythmus anlegen“, „Modus Zyklus“, „Modus
/// Feste Tage“). Liefert eine Nutzermeldung oder null, wenn gespeichert
/// werden darf. [activePlanIds] sind die nicht archivierten Pläne.
String? validateScheduleSlots(
  TrainingScheduleMode mode,
  List<TrainingScheduleSlot> slots,
  Set<String> activePlanIds,
) {
  if (mode == TrainingScheduleMode.weekly && slots.length != 7) {
    return 'Feste Tage brauchen genau sieben Tage.';
  }
  if (mode == TrainingScheduleMode.cycle &&
      (slots.isEmpty || slots.length > maxCycleSlots)) {
    return 'Ein Zyklus hat 1 bis $maxCycleSlots Tage.';
  }
  if (!slots.any((slot) => activePlanIds.contains(slot.planId))) {
    return 'Mindestens ein Tag braucht einen Plan.';
  }
  return null;
}
