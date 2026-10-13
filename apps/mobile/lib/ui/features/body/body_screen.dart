import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/body/body_tracking.dart';
import 'body_view_model.dart';

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
        navigationBar: const CupertinoNavigationBar(middle: Text('Körper')),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (model.isLoading && model.snapshot == null)
                const Center(child: CupertinoActivityIndicator()),
              if (model.errorMessage != null)
                Text(
                  model.errorMessage!,
                  key: const ValueKey('body-error'),
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              _sectionTitle(context, 'Aktives Ziel'),
              _activeGoal(model.snapshot?.activeGoal),
              _sectionTitle(context, 'Ziel festlegen'),
              CupertinoSlidingSegmentedControl<BodyGoalKind>(
                groupValue: _kind,
                children: const {
                  BodyGoalKind.bulk: Text('Aufbau'),
                  BodyGoalKind.maintain: Text('Halten'),
                  BodyGoalKind.cut: Text('Abnehmen'),
                },
                onValueChanged: (value) => setState(() => _kind = value!),
              ),
              CupertinoSlidingSegmentedControl<BodyWeightUnit>(
                groupValue: _unit,
                children: const {
                  BodyWeightUnit.kilograms: Text('kg'),
                  BodyWeightUnit.pounds: Text('lb'),
                },
                onValueChanged: (value) => setState(() => _unit = value!),
              ),
              _field(
                'Startgewicht (${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'})',
                _startWeight,
                decimal: true,
              ),
              _field(
                'Zielgewicht (${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'})',
                _targetWeight,
                decimal: true,
              ),
              Text('Start: ${_dateOnly(_startDate)}'),
              CupertinoButton(
                key: const ValueKey('body-start-date'),
                padding: EdgeInsets.zero,
                onPressed: () => _pickDate(start: true),
                child: const Text('Startdatum wählen'),
              ),
              Text(
                'Zieldatum: ${_targetDate == null ? 'ohne' : _dateOnly(_targetDate!)}',
              ),
              CupertinoButton(
                key: const ValueKey('body-target-date'),
                padding: EdgeInsets.zero,
                onPressed: () => _pickDate(start: false),
                child: const Text('Zieldatum wählen'),
              ),
              CupertinoButton.filled(
                key: const ValueKey('body-save-goal'),
                onPressed: model.isSaving ? null : () => _saveGoal(model),
                child: const Text('Ziel speichern'),
              ),
              _sectionTitle(context, 'Tagescheck-in'),
              _field(
                'Gewicht (${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'})',
                _checkInWeight,
                decimal: true,
              ),
              _field('Kalorien (kcal)', _calories, decimal: true),
              _field('Protein (g)', _protein, decimal: true),
              _field('Kohlenhydrate (g)', _carbs, decimal: true),
              _field('Fett (g)', _fat, decimal: true),
              _field('Schritte', _steps),
              _field('Schlaf (Minuten)', _sleep),
              CupertinoButton.filled(
                key: const ValueKey('body-save-checkin'),
                onPressed: model.isSaving ? null : () => _saveCheckIn(model),
                child: const Text('Check-in für heute speichern'),
              ),
              _sectionTitle(context, 'Verlauf'),
              for (final item in model.snapshot?.goalHistory ?? const [])
                Text(
                  '${item.value.kind.name} · ${item.value.startDate} – ${item.value.endedAtUtc ?? ''}',
                ),
              for (final item in model.snapshot?.checkIns ?? const [])
                Text(
                  '${item.value.localDate} · ${_formatWeight(item.value.weightKg)}',
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _activeGoal(({String id, BodyGoal value})? goal) => Text(
    goal == null
        ? 'Noch kein aktives Ziel'
        : '${goal.value.kind.name} · ${_formatWeight(goal.value.startWeightKg)} → ${_formatWeight(goal.value.targetWeightKg)}',
    key: const ValueKey('body-active-goal'),
  );

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      title,
      style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool decimal = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: CupertinoTextField(
      controller: controller,
      placeholder: label,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    ),
  );

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startDate : _targetDate ?? _startDate;
    var selected = current;
    final chosen = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        height: 310,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                key: const ValueKey('body-date-done'),
                onPressed: () => Navigator.of(context).pop(selected),
                child: const Text('Fertig'),
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
      setState(() {
        if (start) _startDate = chosen;
        if (!start) _targetDate = chosen;
      });
    }
  }

  Future<void> _saveGoal(BodyViewModel model) async {
    await model.saveGoal(
      kind: _kind,
      startWeightKg: weightToKilograms(
        double.tryParse(_startWeight.text) ?? double.nan,
        _unit,
      ),
      targetWeightKg: weightToKilograms(
        double.tryParse(_targetWeight.text) ?? double.nan,
        _unit,
      ),
      startDate: _dateOnly(_startDate),
      targetDate: _targetDate == null ? null : _dateOnly(_targetDate!),
    );
  }

  Future<void> _saveCheckIn(BodyViewModel model) async {
    await model.saveCheckIn(
      localDate: _dateOnly(DateTime.now()),
      weightKg: weightToKilograms(
        double.tryParse(_checkInWeight.text) ?? double.nan,
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
      : double.tryParse(controller.text) ?? double.nan;

  int? _optionalInt(TextEditingController controller) =>
      controller.text.trim().isEmpty
      ? null
      : int.tryParse(controller.text) ?? -1;

  String _formatWeight(double kilograms) =>
      '${weightForDisplay(kilograms, _unit).toStringAsFixed(1)} ${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'}';

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
