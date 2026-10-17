import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'body_view_model.dart';

const _checkInTitle = 'Check-in';

class BodyScreen extends StatefulWidget {
  const BodyScreen({required this.viewModel, super.key});

  final BodyViewModel viewModel;

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  late final TextEditingController _startWeight = TextEditingController();
  late final TextEditingController _targetWeight = TextEditingController();
  late final TextEditingController _checkInWeight = TextEditingController();
  late final TextEditingController _calories = TextEditingController();
  late final TextEditingController _protein = TextEditingController();
  late final TextEditingController _carbs = TextEditingController();
  late final TextEditingController _fat = TextEditingController();
  late final TextEditingController _steps = TextEditingController();
  late final TextEditingController _sleep = TextEditingController();
  BodyGoalKind _kind = BodyGoalKind.maintain;
  BodyWeightUnit _unit = BodyWeightUnit.kilograms;
  DateTime _startDate = DateTime.now();
  DateTime? _targetDate;
  DateTime _checkInDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.load(),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _startWeight,
      _targetWeight,
      _checkInWeight,
      _calories,
      _protein,
      _carbs,
      _fat,
      _steps,
      _sleep,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.viewModel,
    child: Consumer<BodyViewModel>(
      builder: (context, model, _) {
        final colors = GainerDesign.colorsOf(context);
        return GainerScaffold(
          title: _checkInTitle,
          children: [
            if (model.isLoading && model.snapshot == null)
              const Center(child: CupertinoActivityIndicator()),
            if (model.errorMessage != null)
              _NoticeCard(
                key: const ValueKey('body-error'),
                message: model.errorMessage!,
              ),
            Text(
              'Dein aktueller Stand und tägliche Check-ins',
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 20),
            _goalCard(context, model),
            const SizedBox(height: 12),
            _todayCard(context, model),
            const SizedBox(height: 12),
            GainerPillButton(
              key: const ValueKey('body-open-checkin'),
              label: 'Check-in eintragen',
              expand: true,
              onPressed: model.isSaving ? null : () => _openCheckIn(model),
            ),
            const SizedBox(height: 8),
            GainerPillButton(
              key: const ValueKey('body-open-goal'),
              label: model.snapshot?.activeGoal == null
                  ? 'Körperziel festlegen'
                  : 'Ziel bearbeiten',
              variant: GainerPillVariant.tonal,
              expand: true,
              onPressed: () => _openGoal(model),
            ),
            _sectionTitle(context, 'Verlauf'),
            _history(context, model.snapshot, isLoading: model.isLoading),
          ],
        );
      },
    ),
  );

  Widget _goalCard(BuildContext context, BodyViewModel model) => _OverviewCard(
    title: 'Aktives Ziel',
    icon: CupertinoIcons.scope,
    child: model.snapshot == null
        ? Text(
            model.isLoading
                ? 'Zieldaten werden geladen …'
                : 'Zieldaten sind nicht verfügbar.',
          )
        : _activeGoal(context, model.snapshot!.activeGoal),
  );

  Widget _todayCard(BuildContext context, BodyViewModel model) => _OverviewCard(
    title: 'Heute',
    icon: CupertinoIcons.calendar,
    child: model.snapshot == null
        ? Text(
            model.isLoading
                ? 'Check-in wird geladen …'
                : 'Check-in konnte nicht geladen werden.',
          )
        : _todaySummary(model.snapshot!.checkIns),
  );

  /* old editor fields are presented in focused native sheets below */
  Widget _editorFields(
    BuildContext context,
    BodyViewModel model, {
    required bool goal,
    required StateSetter rebuild,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (goal) ...[
        GainerSegmentedControl<BodyGoalKind>(
          value: _kind,
          options: const {
            BodyGoalKind.bulk: 'Aufbau',
            BodyGoalKind.maintain: 'Halten',
            BodyGoalKind.cut: 'Abnehmen',
          },
          onChanged: (value) => rebuild(() => _kind = value),
        ),
        const SizedBox(height: 12),
        GainerSegmentedControl<BodyWeightUnit>(
          key: const ValueKey('body-goal-weight-unit'),
          value: _unit,
          options: const {
            BodyWeightUnit.kilograms: 'kg',
            BodyWeightUnit.pounds: 'lb',
          },
          onChanged: (value) => rebuild(() => _changeUnit(value)),
        ),
        _field(
          context,
          'Startgewicht (${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'})',
          _startWeight,
          decimal: true,
          key: const ValueKey('body-start-weight'),
        ),
        _field(
          context,
          'Zielgewicht (${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'})',
          _targetWeight,
          decimal: true,
          key: const ValueKey('body-target-weight'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Startdatum · ${_prettyDate(_dateOnly(_startDate))}'),
        ),
        GainerPillButton(
          key: const ValueKey('body-start-date'),
          label: 'Startdatum wählen',
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: () => _pickDate(start: true, rebuild: rebuild),
        ),
        Text(
          'Zieldatum · ${_targetDate == null ? 'Kein Datum' : _prettyDate(_dateOnly(_targetDate!))}',
        ),
        GainerPillButton(
          key: const ValueKey('body-target-date'),
          label: 'Zieldatum wählen',
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: () => _pickDate(start: false, rebuild: rebuild),
        ),
      ],
      if (!goal) ...[
        _field(
          context,
          'Gewicht (${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'})',
          _checkInWeight,
          decimal: true,
          key: const ValueKey('body-checkin-weight'),
        ),
        _field(context, 'Kalorien (kcal)', _calories, decimal: true),
        _field(context, 'Protein (g)', _protein, decimal: true),
        _field(context, 'Kohlenhydrate (g)', _carbs, decimal: true),
        _field(context, 'Fett (g)', _fat, decimal: true),
        _field(context, 'Schritte', _steps),
        _field(context, 'Schlaf (Minuten)', _sleep),
      ],
    ],
  );

  Future<void> _openGoal(BodyViewModel model) async {
    final value = model.snapshot?.activeGoal?.value;
    _kind = value?.kind ?? BodyGoalKind.maintain;
    _startWeight.text = value == null
        ? ''
        : _editableWeight(weightForDisplay(value.startWeightKg, _unit));
    _targetWeight.text = value == null
        ? ''
        : _editableWeight(weightForDisplay(value.targetWeightKg, _unit));
    _startDate = DateTime.tryParse(value?.startDate ?? '') ?? DateTime.now();
    _targetDate = DateTime.tryParse(value?.targetDate ?? '');
    await _showEditor(model, goal: true);
  }

  void _changeUnit(BodyWeightUnit next) {
    if (next == _unit) {
      return;
    }
    for (final controller in [_startWeight, _targetWeight, _checkInWeight]) {
      final value = _parseEditableDouble(controller);
      if (value == null) {
        continue;
      }
      final kilograms = weightToKilograms(value, _unit);
      controller.text = _editableWeight(weightForDisplay(kilograms, next));
    }
    _unit = next;
  }

  Future<void> _openCheckIn(BodyViewModel model) async {
    final now = DateTime.now();
    _checkInDate = DateTime(now.year, now.month, now.day);
    _prefillCheckIn(model, _checkInDate);
    await _showEditor(model, goal: false);
  }

  void _prefillCheckIn(BodyViewModel model, DateTime date) {
    final localDate = _dateOnly(date);
    final existing = model.snapshot?.checkIns
        .where((item) => item.value.localDate == localDate)
        .firstOrNull
        ?.value;
    _checkInWeight.text = existing == null
        ? ''
        : _editableWeight(weightForDisplay(existing.weightKg, _unit));
    _calories.text = _editableNumber(existing?.caloriesKcal);
    _protein.text = _editableNumber(existing?.proteinGrams);
    _carbs.text = _editableNumber(existing?.carbohydrateGrams);
    _fat.text = _editableNumber(existing?.fatGrams);
    _steps.text = existing?.steps?.toString() ?? '';
    _sleep.text = existing?.sleepMinutes?.toString() ?? '';
  }

  Future<void> _showEditor(BodyViewModel model, {required bool goal}) =>
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => ChangeNotifierProvider.value(
          value: model,
          child: Consumer<BodyViewModel>(
            builder: (sheetContext, liveModel, _) => StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                final media = MediaQuery.of(sheetContext);
                final colors = GainerDesign.colorsOf(sheetContext);
                return Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: Container(
                    height: (media.size.height - media.viewInsets.bottom) * .94,
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(GainerRadii.card),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          _editorToolbar(sheetContext, liveModel, goal: goal),
                          Expanded(
                            child: ListView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                28,
                              ),
                              children: [
                                if (liveModel.errorMessage case final error?)
                                  _NoticeCard(message: error),
                                if (!goal)
                                  ..._checkInHeaderChildren(
                                    sheetContext,
                                    liveModel,
                                    setSheetState,
                                  ),
                                const SizedBox(height: 16),
                                _editorFields(
                                  sheetContext,
                                  liveModel,
                                  goal: goal,
                                  rebuild: setSheetState,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

  Widget _editorToolbar(
    BuildContext sheetContext,
    BodyViewModel liveModel, {
    required bool goal,
  }) {
    final colors = GainerDesign.colorsOf(sheetContext);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: GainerPillButton(
              label: 'Abbrechen',
              variant: GainerPillVariant.tonal,
              onPressed: liveModel.isSaving
                  ? null
                  : () => Navigator.of(sheetContext).pop(),
            ),
          ),
          Expanded(
            child: Text(
              goal ? 'Körperziel' : _checkInTitle,
              textAlign: TextAlign.center,
              softWrap: true,
              style: GainerTypography.title.copyWith(color: colors.primaryText),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (liveModel.isSaving) ...[
                  const CupertinoActivityIndicator(),
                  const SizedBox(width: GainerSpacing.xs),
                ],
                Flexible(
                  child: GainerPillButton(
                    key: ValueKey(
                      goal ? 'body-save-goal' : 'body-save-checkin',
                    ),
                    label: 'Sichern',
                    onPressed: liveModel.isSaving
                        ? null
                        : () => _saveFromSheet(
                            sheetContext,
                            liveModel,
                            goal: goal,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFromSheet(
    BuildContext sheetContext,
    BodyViewModel liveModel, {
    required bool goal,
  }) async {
    if (goal) {
      await _saveGoal(liveModel);
    } else {
      await _saveCheckIn(liveModel);
    }
    if (mounted &&
        liveModel.errorMessage == null &&
        sheetContext.mounted &&
        ModalRoute.of(sheetContext)?.isCurrent == true) {
      Navigator.of(sheetContext).pop();
    }
  }

  List<Widget> _checkInHeaderChildren(
    BuildContext sheetContext,
    BodyViewModel liveModel,
    StateSetter setSheetState,
  ) {
    final colors = GainerDesign.colorsOf(sheetContext);
    return [
      CupertinoButton(
        key: const ValueKey('body-checkin-date'),
        minimumSize: const Size(double.infinity, 48),
        padding: EdgeInsets.zero,
        onPressed: liveModel.isSaving
            ? null
            : () => _pickCheckInDate(liveModel, setSheetState),
        child: Row(
          children: [
            Icon(CupertinoIcons.calendar, color: colors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Datum · ${_prettyDate(_dateOnly(_checkInDate))}',
                softWrap: true,
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: colors.secondaryText,
            ),
          ],
        ),
      ),
      Text(
        'Check-in für ${_prettyDate(_dateOnly(_checkInDate))}',
        style: GainerTypography.title.copyWith(color: colors.primaryText),
      ),
      const SizedBox(height: 8),
      Text(
        'Gewicht ist erforderlich. Weitere Angaben sind optional.',
        style: GainerTypography.label.copyWith(color: colors.secondaryText),
      ),
    ];
  }

  Widget _todaySummary(List<({String id, DailyCheckIn value})> checkIns) {
    final today = _dateOnly(DateTime.now());
    final entry = checkIns
        .where((item) => item.value.localDate == today)
        .firstOrNull
        ?.value;
    if (entry == null) {
      return const Text('Noch kein Check-in für heute');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetricPill(label: 'Gewicht', value: _formatWeight(entry.weightKg)),
        if (entry.caloriesKcal case final calories?)
          _MetricPill(
            label: 'Kalorien',
            value: '${calories.toStringAsFixed(0)} kcal',
          ),
        if (entry.steps case final steps?)
          _MetricPill(label: 'Schritte', value: steps.toString()),
      ],
    );
  }

  Widget _history(
    BuildContext context,
    BodyTrackingSnapshot? snapshot, {
    required bool isLoading,
  }) {
    if (snapshot == null) {
      return const _OverviewCard(
        title: 'Verlauf',
        icon: CupertinoIcons.chart_bar,
        child: Text('Verlauf wird geladen …'),
      );
    }
    final entries = snapshot.checkIns;
    final goals = snapshot.goalHistory;
    if (entries.isEmpty && goals.isEmpty) {
      return _OverviewCard(
        title: 'Verlauf',
        icon: CupertinoIcons.chart_bar,
        child: Text(
          isLoading ? 'Verlauf wird geladen …' : 'Deine Einträge erscheinen hier, sobald du deinen ersten Check-in gespeichert hast.',
        ),
      );
    }
    final colors = GainerDesign.colorsOf(context);
    final rows = <Widget>[
      for (final item in goals)
        _HistoryRow(
          top:
              '${_goalLabel(item.value.kind)} · ${_prettyDate(item.value.startDate)}',
          bottom:
              '${_formatWeight(item.value.startWeightKg)} → ${_formatWeight(item.value.targetWeightKg)}',
        ),
      if (entries.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Text('Noch keine Check-ins gespeichert.'),
        ),
      for (final item in entries.take(10))
        _HistoryRow(
          top: _prettyDate(item.value.localDate),
          bottom: _formatWeight(item.value.weightKg),
        ),
    ];
    return _OverviewCard(
      title: 'Verlauf',
      icon: CupertinoIcons.chart_bar,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 0.5, color: colors.separator),
            rows[i],
          ],
        ],
      ),
    );
  }

  String _prettyDate(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return date;
    }
    const months = [
      'Jan',
      'Feb',
      'Mär',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez',
    ];
    return '${parsed.day}. ${months[parsed.month - 1]} ${parsed.year}';
  }

  Widget _activeGoal(
    BuildContext context,
    ({String id, BodyGoal value})? goal,
  ) {
    final colors = GainerDesign.colorsOf(context);
    return goal == null
        ? const Text('Noch kein aktives Ziel')
        : Column(
            key: const ValueKey('body-active-goal'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _goalLabel(goal.value.kind),
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_formatWeight(goal.value.startWeightKg)}  →  ${_formatWeight(goal.value.targetWeightKg)}',
              ),
              if (goal.value.targetDate case final date?)
                Text(
                  'Zieldatum · ${_prettyDate(date)}',
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
            ],
          );
  }

  String _goalLabel(BodyGoalKind kind) => switch (kind) {
    BodyGoalKind.bulk => 'Muskelaufbau',
    BodyGoalKind.maintain => 'Gewicht halten',
    BodyGoalKind.cut => 'Gewicht reduzieren',
  };

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      title,
      style: GainerTypography.title.copyWith(
        fontSize: 20,
        color: GainerDesign.colorsOf(context).primaryText,
      ),
    ),
  );

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool decimal = false,
    Key? key,
  }) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 5),
          CupertinoTextField(
            key: key,
            controller: controller,
            placeholder: 'Eintragen',
            placeholderStyle: GainerTypography.body.copyWith(
              color: colors.placeholderText,
            ),
            style: GainerTypography.body.copyWith(color: colors.primaryText),
            minLines: 1,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(GainerRadii.field),
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({
    required bool start,
    required StateSetter rebuild,
  }) async {
    final current = start ? _startDate : _targetDate ?? _startDate;
    var selected = current;
    final chosen = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        height: 310,
        color: GainerDesign.colorsOf(context).background,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GainerPillButton(
                      key: const ValueKey('body-date-cancel'),
                      label: 'Abbrechen',
                      variant: GainerPillVariant.tonal,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: GainerSpacing.xs),
                  Expanded(
                    child: GainerPillButton(
                      key: const ValueKey('body-date-done'),
                      label: 'Fertig',
                      onPressed: () => Navigator.of(context).pop(selected),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: current,
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      rebuild(() {
        if (start) _startDate = chosen;
        if (!start) _targetDate = chosen;
      });
    }
  }

  Future<void> _pickCheckInDate(
    BodyViewModel model,
    StateSetter rebuild,
  ) async {
    var selected = _checkInDate;
    final chosen = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        key: const ValueKey('body-checkin-date-picker'),
        height: 310,
        color: GainerDesign.colorsOf(context).background,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GainerPillButton(
                      label: 'Abbrechen',
                      variant: GainerPillVariant.tonal,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: GainerSpacing.xs),
                  Expanded(
                    child: GainerPillButton(
                      key: const ValueKey('body-checkin-date-done'),
                      label: 'Fertig',
                      onPressed: () => Navigator.of(context).pop(selected),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                key: const ValueKey('body-checkin-date-wheel'),
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _checkInDate,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      rebuild(() {
        _checkInDate = DateTime(chosen.year, chosen.month, chosen.day);
        _prefillCheckIn(model, _checkInDate);
      });
    }
  }

  Future<void> _saveGoal(BodyViewModel model) async {
    await model.saveGoal(
      kind: _kind,
      startWeightKg: weightToKilograms(
        _parseEditableDouble(_startWeight) ?? double.nan,
        _unit,
      ),
      targetWeightKg: weightToKilograms(
        _parseEditableDouble(_targetWeight) ?? double.nan,
        _unit,
      ),
      startDate: _dateOnly(_startDate),
      targetDate: _targetDate == null ? null : _dateOnly(_targetDate!),
    );
  }

  Future<void> _saveCheckIn(BodyViewModel model) async {
    await model.saveCheckIn(
      localDate: _dateOnly(_checkInDate),
      weightKg: weightToKilograms(
        _parseEditableDouble(_checkInWeight) ?? double.nan,
        _unit,
      ),
      caloriesKcal: _optionalDouble(_calories),
      proteinGrams: _optionalDouble(_protein),
      carbohydrateGrams: _optionalDouble(_carbs),
      fatGrams: _optionalDouble(_fat),
      steps: _optionalInt(_steps),
      sleepMinutes: _optionalInt(_sleep),
    );
  }

  double? _optionalDouble(TextEditingController controller) =>
      controller.text.trim().isEmpty
      ? null
      : _parseEditableDouble(controller) ?? double.nan;

  double? _parseEditableDouble(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  int? _optionalInt(TextEditingController controller) =>
      controller.text.trim().isEmpty
      ? null
      : int.tryParse(controller.text) ?? -1;

  String _formatWeight(double kilograms) =>
      '${weightForDisplay(kilograms, _unit).toStringAsFixed(1)} ${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'}';

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _editableNumber(num? value) {
    if (value == null) {
      return '';
    }
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  String _editableWeight(double value) {
    final text = value.toStringAsFixed(6);
    final trimmed = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return trimmed.contains('.') ? trimmed : '$trimmed.0';
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.top, required this.bottom});
  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            top,
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
          Text(
            bottom,
            style: GainerTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GainerTypography.cardTitle.copyWith(
                    color: colors.primaryText,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: GainerDesign.colorsOf(context).elevatedSurface,
      borderRadius: BorderRadius.circular(GainerRadii.field),
    ),
    child: Text(
      '$label  $value',
      style: const TextStyle(fontWeight: FontWeight.w500),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.destructive.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(GainerRadii.field),
      ),
      child: Text(message, style: TextStyle(color: colors.destructive)),
    );
  }
}
