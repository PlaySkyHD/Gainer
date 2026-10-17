import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
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
      builder: (context, model, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text(_checkInTitle),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: [
                  if (model.isLoading && model.snapshot == null)
                    const Center(child: CupertinoActivityIndicator()),
                  if (model.errorMessage != null)
                    _NoticeCard(
                      key: const ValueKey('body-error'),
                      message: model.errorMessage!,
                    ),
                  Text(
                    _checkInTitle,
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dein aktueller Stand und tägliche Check-ins',
                    style: TextStyle(color: GainerTheme.secondaryText(context)),
                  ),
                  const SizedBox(height: 20),
                  _goalCard(model),
                  const SizedBox(height: 12),
                  _todayCard(model),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: CupertinoButton.filled(
                      color: GainerTheme.actionColor(context),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      key: const ValueKey('body-open-checkin'),
                      onPressed: model.isSaving
                          ? null
                          : () => _openCheckIn(model),
                      child: const Text(
                        'Check-in eintragen',
                        textAlign: TextAlign.center,
                        softWrap: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    key: const ValueKey('body-open-goal'),
                    minimumSize: const Size(double.infinity, 48),
                    onPressed: () => _openGoal(model),
                    child: Text(
                      model.snapshot?.activeGoal == null
                          ? 'Körperziel festlegen'
                          : 'Ziel bearbeiten',
                    ),
                  ),
                  _sectionTitle(context, 'Verlauf'),
                  _history(model.snapshot, isLoading: model.isLoading),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _goalCard(BodyViewModel model) => _OverviewCard(
    title: 'Aktives Ziel',
    icon: CupertinoIcons.scope,
    child: model.snapshot == null
        ? Text(
            model.isLoading
                ? 'Zieldaten werden geladen …'
                : 'Zieldaten sind nicht verfügbar.',
          )
        : _activeGoal(model.snapshot!.activeGoal),
  );

  Widget _todayCard(BodyViewModel model) => _OverviewCard(
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
        CupertinoSlidingSegmentedControl<BodyGoalKind>(
          groupValue: _kind,
          children: const {
            BodyGoalKind.bulk: Text('Aufbau'),
            BodyGoalKind.maintain: Text('Halten'),
            BodyGoalKind.cut: Text('Abnehmen'),
          },
          onValueChanged: (value) => rebuild(() => _kind = value!),
        ),
        const SizedBox(height: 12),
        CupertinoSlidingSegmentedControl<BodyWeightUnit>(
          key: const ValueKey('body-goal-weight-unit'),
          groupValue: _unit,
          children: const {
            BodyWeightUnit.kilograms: Text('kg'),
            BodyWeightUnit.pounds: Text('lb'),
          },
          onValueChanged: (value) => rebuild(() => _changeUnit(value!)),
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
        CupertinoButton(
          key: const ValueKey('body-start-date'),
          minimumSize: const Size(double.infinity, 48),
          onPressed: () => _pickDate(start: true, rebuild: rebuild),
          child: const Text('Startdatum wählen'),
        ),
        Text(
          'Zieldatum · ${_targetDate == null ? 'Kein Datum' : _prettyDate(_dateOnly(_targetDate!))}',
        ),
        CupertinoButton(
          key: const ValueKey('body-target-date'),
          minimumSize: const Size(double.infinity, 48),
          onPressed: () => _pickDate(start: false, rebuild: rebuild),
          child: const Text('Zieldatum wählen'),
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
                return Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: Container(
                    height: (media.size.height - media.viewInsets.bottom) * .94,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground.resolveFrom(
                        sheetContext,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
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
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: CupertinoButton(
            minimumSize: const Size(64, 48),
            onPressed: liveModel.isSaving
                ? null
                : () => Navigator.of(sheetContext).pop(),
            child: const Text(
              'Abbrechen',
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
        ),
        Expanded(
          child: Text(
            goal ? 'Körperziel' : _checkInTitle,
            textAlign: TextAlign.center,
            softWrap: true,
            style: CupertinoTheme.of(sheetContext).textTheme.navTitleTextStyle,
          ),
        ),
        Expanded(
          child: CupertinoButton(
            key: ValueKey(goal ? 'body-save-goal' : 'body-save-checkin'),
            minimumSize: const Size(64, 48),
            onPressed: liveModel.isSaving
                ? null
                : () => _saveFromSheet(sheetContext, liveModel, goal: goal),
            child: liveModel.isSaving
                ? const CupertinoActivityIndicator()
                : const Text(
                    'Sichern',
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
          ),
        ),
      ],
    ),
  );

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
  ) => [
    CupertinoButton(
      key: const ValueKey('body-checkin-date'),
      minimumSize: const Size(double.infinity, 48),
      padding: EdgeInsets.zero,
      onPressed: liveModel.isSaving
          ? null
          : () => _pickCheckInDate(liveModel, setSheetState),
      child: Row(
        children: [
          const Icon(CupertinoIcons.calendar),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Datum · ${_prettyDate(_dateOnly(_checkInDate))}',
              softWrap: true,
            ),
          ),
          const Spacer(),
          const CupertinoListTileChevron(),
        ],
      ),
    ),
    Text(
      'Check-in für ${_prettyDate(_dateOnly(_checkInDate))}',
      style: CupertinoTheme.of(sheetContext).textTheme.navTitleTextStyle,
    ),
    const SizedBox(height: 8),
    Text(
      'Gewicht ist erforderlich. Weitere Angaben sind optional.',
      style: TextStyle(color: GainerTheme.secondaryText(sheetContext)),
    ),
  ];

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

  Widget _history(BodyTrackingSnapshot? snapshot, {required bool isLoading}) {
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
    return _OverviewCard(
      title: 'Verlauf',
      icon: CupertinoIcons.chart_bar,
      child: Column(
        children: [
          for (final item in goals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_goalLabel(item.value.kind)} · ${_prettyDate(item.value.startDate)}',
                  ),
                  Text(
                    '${_formatWeight(item.value.startWeightKg)} → ${_formatWeight(item.value.targetWeightKg)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Text('Noch keine Check-ins gespeichert.'),
            ),
          for (final item in entries.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_prettyDate(item.value.localDate)),
                  Text(
                    _formatWeight(item.value.weightKg),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
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

  Widget _activeGoal(({String id, BodyGoal value})? goal) => goal == null
      ? const Text('Noch kein aktives Ziel')
      : Column(
          key: const ValueKey('body-active-goal'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _goalLabel(goal.value.kind),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              '${_formatWeight(goal.value.startWeightKg)}  →  ${_formatWeight(goal.value.targetWeightKg)}',
            ),
            if (goal.value.targetDate case final date?)
              Text(
                'Zieldatum · ${_prettyDate(date)}',
                style: const TextStyle(fontSize: 13),
              ),
          ],
        );

  String _goalLabel(BodyGoalKind kind) => switch (kind) {
    BodyGoalKind.bulk => 'Muskelaufbau',
    BodyGoalKind.maintain => 'Gewicht halten',
    BodyGoalKind.cut => 'Gewicht reduzieren',
  };

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      title,
      style: CupertinoTheme.of(context).textTheme.navTitleTextStyle
          .copyWith(fontSize: 20),
    ),
  );

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool decimal = false,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CupertinoTheme.of(context).textTheme.textStyle),
        const SizedBox(height: 5),
        CupertinoTextField(
          key: key,
          controller: controller,
          placeholder: 'Eintragen',
          minLines: 1,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        ),
      ],
    ),
  );

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
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: CupertinoButton(
                      key: const ValueKey('body-date-cancel'),
                      minimumSize: const Size(64, 48),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Abbrechen',
                        textAlign: TextAlign.center,
                        softWrap: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: CupertinoButton(
                      key: const ValueKey('body-date-done'),
                      minimumSize: const Size(64, 48),
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text(
                        'Fertig',
                        textAlign: TextAlign.center,
                        softWrap: true,
                      ),
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
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      minimumSize: const Size(64, 48),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  Expanded(
                    child: CupertinoButton(
                      key: const ValueKey('body-checkin-date-done'),
                      minimumSize: const Size(64, 48),
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text('Fertig'),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: CupertinoColors.separator
            .resolveFrom(context)
            .withValues(alpha: .25),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: CupertinoTheme.of(context).primaryColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
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

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: CupertinoColors.tertiarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(12),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CupertinoColors.systemRed
          .resolveFrom(context)
          .withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: TextStyle(color: CupertinoColors.systemRed.resolveFrom(context)),
    ),
  );
}
