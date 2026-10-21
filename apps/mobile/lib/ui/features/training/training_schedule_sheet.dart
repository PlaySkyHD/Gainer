import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'training_plans_view_model.dart';
import 'training_schedule_format.dart';

/// Öffnet den Rhythmus-Editor (D6). Liefert true, wenn der Rhythmus
/// gespeichert oder gelöscht wurde.
Future<bool> showTrainingScheduleSheet(
  BuildContext context, {
  required TrainingLogRepository repository,
}) async {
  final changed = await showGainerSheet<bool>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => TrainingScheduleEditor(repository: repository),
  );
  return changed ?? false;
}

/// Inhalt des Rhythmus-Editors; öffentlich für Tests und Vorschauen.
class TrainingScheduleEditor extends StatefulWidget {
  const TrainingScheduleEditor({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  State<TrainingScheduleEditor> createState() => _TrainingScheduleEditorState();
}

class _Slot {
  _Slot(this.key, this.planId);

  final int key;
  String? planId;
}

/// Auswahl im Plan-Picker; `planId == null` ist ein Ruhetag.
class _Pick {
  const _Pick(this.planId);

  final String? planId;
}

enum _MenuAction { delete }

class _TrainingScheduleEditorState extends State<TrainingScheduleEditor> {
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _dirty = false;
  String? _saveError;

  List<TrainingPlanModel> _plans = const [];
  TrainingSchedule? _existing;
  late LocalDay _today;

  TrainingScheduleMode _mode = TrainingScheduleMode.cycle;
  List<_Slot> _cycle = [];
  int? _todayKey;
  List<String?> _weekly = List<String?>.filled(7, null);
  var _nextKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await widget.repository.readPlans(includeArchived: true);
      final schedule = await widget.repository.schedule.read();
      if (!mounted) return;
      setState(() {
        _today = widget.repository.schedule.today();
        _plans = plans;
        _existing = schedule;
        _initDraft(schedule);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Der Rhythmus konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  void _initDraft(TrainingSchedule? schedule) {
    final active = [
      for (final plan in _plans)
        if (!plan.isArchived) plan,
    ];
    if (schedule != null && schedule.isCycle) {
      _mode = TrainingScheduleMode.cycle;
      _cycle = [
        for (final slot in schedule.slots) _Slot(_nextKey++, slot.planId),
      ];
      final index = _currentCycleIndex(schedule);
      _todayKey = _cycle.isEmpty ? null : _cycle[index].key;
    } else {
      // Vorschlag: alle aktiven Pläne nacheinander, danach ein Ruhetag.
      _cycle = [
        for (final plan in active.take(maxCycleSlots - 1))
          _Slot(_nextKey++, plan.planId),
        if (active.isNotEmpty) _Slot(_nextKey++, null),
      ];
      _todayKey = _cycle.isEmpty ? null : _cycle.first.key;
    }
    if (schedule != null && !schedule.isCycle && schedule.slots.length == 7) {
      _mode = TrainingScheduleMode.weekly;
      _weekly = [for (final slot in schedule.slots) slot.planId];
    }
    _dirty = schedule == null;
  }

  /// Slot, der heute gilt. An einem pausierten Tag der Slot vor dem nächsten
  /// nicht pausierten Tag.
  int _currentCycleIndex(TrainingSchedule schedule) {
    final length = schedule.slots.length;
    for (var offset = 0; offset <= maxShiftDays * 2; offset++) {
      final index = schedule.cycleSlotIndexOn(_today.addDays(offset));
      if (index != null) return (index - offset) % length;
    }
    return 0;
  }

  Set<String> get _activePlanIds => {
    for (final plan in _plans)
      if (!plan.isArchived) plan.planId,
  };

  TrainingPlanModel? _planOf(String? planId) {
    if (planId == null) return null;
    for (final plan in _plans) {
      if (plan.planId == planId) return plan;
    }
    return null;
  }

  bool _isArchived(String? planId) {
    if (planId == null) return false;
    final plan = _planOf(planId);
    return plan == null || plan.isArchived;
  }

  String _slotName(String? planId) {
    if (planId == null) return 'Ruhetag';
    return _planOf(planId)?.name ?? 'Plan';
  }

  List<TrainingScheduleSlot> get _draftSlots => switch (_mode) {
    TrainingScheduleMode.cycle => [
      for (final slot in _cycle) TrainingScheduleSlot(planId: slot.planId),
    ],
    TrainingScheduleMode.weekly => [
      for (final planId in _weekly) TrainingScheduleSlot(planId: planId),
    ],
  };

  int get _todayIndex {
    final index = _cycle.indexWhere((slot) => slot.key == _todayKey);
    return index < 0 ? 0 : index;
  }

  String? get _validation =>
      validateScheduleSlots(_mode, _draftSlots, _activePlanIds);

  /// Stand für die Vorschau: unverändert der gespeicherte Rhythmus mit seinen
  /// Verschiebungen, sonst der Entwurf ab heute.
  TrainingSchedule? get _previewSchedule {
    if (!_dirty && _existing != null) return _existing;
    if (_validation != null) return null;
    return TrainingSchedule.create(
      scheduleId: 'preview',
      mode: _mode,
      slots: _draftSlots,
      today: _today,
      todaySlotIndex: _mode == TrainingScheduleMode.cycle ? _todayIndex : 0,
    );
  }

  void _edit(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
      _saveError = null;
    });
  }

  Future<_Pick?> _pick({required bool allowRest, String? title}) {
    final active = [
      for (final plan in _plans)
        if (!plan.isArchived) plan,
    ];
    return showGainerActionSheet<_Pick>(
      context: context,
      title: title ?? 'Plan wählen',
      groups: [
        if (allowRest)
          const [
            GainerSheetAction(
              label: 'Ruhetag',
              icon: CupertinoIcons.moon_zzz,
              value: _Pick(null),
            ),
          ],
        if (active.isNotEmpty)
          [
            for (final plan in active)
              GainerSheetAction(
                label: plan.name,
                icon: CupertinoIcons.flame,
                value: _Pick(plan.planId),
              ),
          ],
      ],
    );
  }

  Future<void> _addPlan() async {
    final pick = await _pick(allowRest: false);
    if (pick == null || !mounted) return;
    _edit(() {
      final slot = _Slot(_nextKey++, pick.planId);
      _cycle = [..._cycle, slot];
      _todayKey ??= slot.key;
    });
  }

  void _addRest() => _edit(() {
    final slot = _Slot(_nextKey++, null);
    _cycle = [..._cycle, slot];
    _todayKey ??= slot.key;
  });

  Future<void> _changeCycleSlot(_Slot slot) async {
    final pick = await _pick(allowRest: true);
    if (pick == null || !mounted) return;
    _edit(() => slot.planId = pick.planId);
  }

  void _removeCycleSlot(_Slot slot) => _edit(() {
    final index = _cycle.indexOf(slot);
    _cycle = [..._cycle]..remove(slot);
    if (_todayKey == slot.key) {
      _todayKey = _cycle.isEmpty
          ? null
          : _cycle[index.clamp(0, _cycle.length - 1)].key;
    }
  });

  void _reorder(int oldIndex, int newIndex) => _edit(() {
    final slots = [..._cycle];
    slots.insert(newIndex, slots.removeAt(oldIndex));
    _cycle = slots;
  });

  Future<void> _chooseToday() async {
    final key = await showGainerActionSheet<int>(
      context: context,
      title: 'Heute ist',
      groups: [
        [
          for (var i = 0; i < _cycle.length; i++)
            GainerSheetAction(
              label: 'Tag ${i + 1} · ${_slotName(_cycle[i].planId)}',
              icon: _cycle[i].key == _todayKey
                  ? CupertinoIcons.checkmark
                  : CupertinoIcons.circle,
              value: _cycle[i].key,
            ),
        ],
      ],
    );
    if (key == null || !mounted) return;
    _edit(() => _todayKey = key);
  }

  Future<void> _changeWeekday(int index) async {
    final pick = await _pick(
      allowRest: true,
      title: scheduleWeekdayLong(index),
    );
    if (pick == null || !mounted) return;
    _edit(() => _weekly = [..._weekly]..[index] = pick.planId);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.repository.schedule.saveRhythm(
        mode: _mode,
        slots: _draftSlots,
        todaySlotIndex: _mode == TrainingScheduleMode.cycle ? _todayIndex : 0,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = planErrorMessage(
          error,
          'Der Rhythmus konnte nicht gespeichert werden.',
        );
      });
    }
  }

  Future<void> _openMenu() async {
    final action = await showGainerActionSheet<_MenuAction>(
      context: context,
      title: 'Rhythmus',
      groups: const [
        [
          GainerSheetAction(
            label: 'Rhythmus löschen',
            icon: CupertinoIcons.trash,
            value: _MenuAction.delete,
            destructive: true,
          ),
        ],
      ],
    );
    if (action != _MenuAction.delete || !mounted) return;
    final confirmed = await confirmGainerDelete(
      context,
      title: 'Rhythmus löschen?',
      message: 'Geplante Trainings verschwinden. Deine beendeten Trainings bleiben erhalten.',
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.schedule.delete();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _saveError = planErrorMessage(
          error,
          'Der Rhythmus konnte nicht gelöscht werden.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final validation = _loading ? null : _validation;
    final canSave = !_loading && !_saving && _dirty && validation == null;
    return Column(
      children: [
        // Eigene Kopfzeile: Neben „Speichern“ braucht das Kontextmenü Platz,
        // der Titel schrumpft bei großer Schrift statt umzubrechen.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GainerSpacing.xs,
            GainerSpacing.xs,
            GainerSpacing.s,
            0,
          ),
          child: Row(
            children: [
              GainerToolbarButton(
                icon: CupertinoIcons.xmark,
                semanticLabel: 'Schließen',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Rhythmus',
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ),
              if (_existing != null)
                GainerToolbarButton(
                  key: const ValueKey('schedule-menu'),
                  icon: CupertinoIcons.ellipsis,
                  semanticLabel: 'Weitere Aktionen',
                  onPressed: _saving ? null : _openMenu,
                ),
              // Vorrang vor dem Titel; bricht nur bei sehr großer Schrift um.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.6,
                ),
                child: GainerPillButton(
                  key: const ValueKey('schedule-save'),
                  label: 'Speichern',
                  isLoading: _saving,
                  onPressed: canSave ? _save : null,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body(colors, validation)),
      ],
    );
  }

  Widget _body(GainerColors colors, String? validation) {
    if (_loading) return const Center(child: CupertinoActivityIndicator());
    if (_loadError case final message?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(GainerSpacing.m),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
      );
    }
    final existing = _existing;
    final resetsDayChanges =
        _dirty &&
        existing != null &&
        (existing.shifts.isNotEmpty || existing.exceptions.isNotEmpty);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.s,
        GainerSpacing.m,
        GainerSpacing.l,
      ),
      children: [
        GainerSegmentedControl<TrainingScheduleMode>(
          options: const {
            TrainingScheduleMode.cycle: 'Zyklus',
            TrainingScheduleMode.weekly: 'Feste Tage',
          },
          value: _mode,
          onChanged: (mode) {
            if (mode != _mode) _edit(() => _mode = mode);
          },
        ),
        const SizedBox(height: GainerSpacing.m),
        if (_activePlanIds.isEmpty)
          _Hint(
            text: 'Lege zuerst einen Plan an, z. B. „Push“.',
            color: colors.secondaryText,
          )
        else if (_mode == TrainingScheduleMode.cycle)
          ..._cycleEditor(colors)
        else
          _weeklyEditor(),
        if (validation != null && _activePlanIds.isNotEmpty)
          _Hint(
            key: const ValueKey('schedule-validation'),
            text: validation,
            color: colors.warning,
          ),
        if (resetsDayChanges)
          _Hint(
            text: 'Beim Speichern entfallen Verschiebungen und übersprungene Tage.',
            color: colors.secondaryText,
          ),
        if (_saveError case final message?)
          _Hint(text: message, color: colors.destructive),
        if (_previewSchedule case final preview?) ...[
          const SizedBox(height: GainerSpacing.l),
          _preview(preview, colors),
        ],
      ],
    );
  }

  List<Widget> _cycleEditor(GainerColors colors) {
    final full = _cycle.length >= maxCycleSlots;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          GainerSpacing.m,
          0,
          GainerSpacing.m,
          GainerSpacing.xs,
        ),
        child: Text(
          'Reihenfolge',
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
      ),
      if (_cycle.isNotEmpty)
        CustomScrollView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverReorderableList(
              itemCount: _cycle.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) => _cycleRow(index, colors),
            ),
          ],
        ),
      Wrap(
        spacing: GainerSpacing.xs,
        runSpacing: GainerSpacing.xs,
        children: [
          GainerPillButton(
            key: const ValueKey('schedule-add-plan'),
            label: 'Plan',
            icon: CupertinoIcons.add,
            variant: GainerPillVariant.tonal,
            onPressed: full ? null : _addPlan,
          ),
          GainerPillButton(
            key: const ValueKey('schedule-add-rest'),
            label: 'Ruhetag',
            icon: CupertinoIcons.add,
            variant: GainerPillVariant.tonal,
            onPressed: full ? null : _addRest,
          ),
        ],
      ),
      if (_cycle.isNotEmpty) ...[
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerListRow(
              key: const ValueKey('schedule-today'),
              title:
                  'Heute ist: Tag ${_todayIndex + 1} · '
                  '${_slotName(_cycle[_todayIndex].planId)}',
              showChevron: true,
              onTap: _chooseToday,
            ),
          ],
        ),
      ],
    ];
  }

  Widget _cycleRow(int index, GainerColors colors) {
    final slot = _cycle[index];
    final archived = _isArchived(slot.planId);
    final subtitle = [
      'Tag ${index + 1}',
      if (slot.key == _todayKey) 'heute',
      if (archived) 'Plan archiviert',
    ].join(' · ');
    return Padding(
      key: ValueKey('slot-${slot.key}'),
      padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
      child: GainerCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GainerRadii.card),
          child: GainerSwipeToDelete(
            dismissKey: ValueKey('slot-dismiss-${slot.key}'),
            label: 'Entfernen',
            confirm: () async => true,
            onDeleted: () => _removeCycleSlot(slot),
            child: GainerListRow(
              title: _slotName(slot.planId),
              subtitle: subtitle,
              leadingIcon: slot.planId == null
                  ? CupertinoIcons.moon_zzz
                  : CupertinoIcons.flame,
              onTap: () => _changeCycleSlot(slot),
              trailing: ReorderableDragStartListener(
                index: index,
                child: SizedBox(
                  width: GainerRadii.iconButtonDiameter,
                  height: GainerRadii.iconButtonDiameter,
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    color: colors.secondaryText,
                    semanticLabel: 'Verschieben',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weeklyEditor() {
    return GainerGroupedSection(
      header: 'Wochentage',
      children: [
        for (var i = 0; i < 7; i++)
          GainerListRow(
            key: ValueKey('schedule-weekday-$i'),
            title: scheduleWeekdayLong(i),
            subtitle: [
              if (_today.weekday - 1 == i) 'heute',
              if (_isArchived(_weekly[i])) 'Plan archiviert',
            ].join(' · ').nullIfEmpty,
            value: _slotName(_weekly[i]),
            showChevron: true,
            onTap: () => _changeWeekday(i),
          ),
      ],
    );
  }

  Widget _preview(TrainingSchedule schedule, GainerColors colors) {
    final projection = TrainingScheduleProjection(
      schedule: schedule,
      plans: _plans,
      workouts: const [],
      today: _today,
    );
    final days = projection.days(_today, _today.addDays(13));
    return GainerGroupedSection(
      header: 'Nächste 14 Tage',
      children: [
        for (var i = 0; i < days.length; i++)
          _PreviewRow(
            day: i == 0
                ? 'Heute'
                : i == 1
                ? 'Morgen'
                : scheduleDateLabel(days[i].date),
            value: _previewValue(days[i]),
            highlight: days[i].effective.isNotEmpty,
          ),
      ],
    );
  }

  String _previewValue(ScheduleDay day) {
    final plans = day.effective;
    if (plans.isNotEmpty) return plans.map((t) => t.planName).join(' · ');
    if (day.baseKind == ScheduleBaseKind.paused) return 'Pausiert';
    final away = day.trainings.firstOrNull;
    if (away != null) return scheduledStatusLabel(away, _today);
    return 'Ruhetag';
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.s,
        GainerSpacing.m,
        0,
      ),
      child: Text(text, style: GainerTypography.label.copyWith(color: color)),
    );
  }
}

/// Kompakte Zeile der Vorschau: Tag links, Plan rechts.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.day,
    required this.value,
    required this.highlight,
  });

  final String day;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              day,
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: GainerSpacing.xs),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GainerTypography.label.copyWith(
                color: highlight ? colors.primaryText : colors.secondaryText,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
