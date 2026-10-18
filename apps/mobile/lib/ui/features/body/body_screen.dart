import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'body_view_model.dart';

const _checkInTitle = 'Check-in';

const _goalFieldKeys = {'startWeightKg', 'targetWeightKg'};
const _checkInFieldKeys = {
  'weightKg',
  'caloriesKcal',
  'proteinGrams',
  'carbohydrateGrams',
  'fatGrams',
  'steps',
  'sleepMinutes',
};

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
      builder: (context, model, _) => GainerScaffold(
        title: _checkInTitle,
        trailing: [
          GainerToolbarButton(
            key: const ValueKey('body-open-checkin'),
            icon: CupertinoIcons.add,
            semanticLabel: 'Check-in eintragen',
            onPressed: model.isSaving ? null : () => _openCheckIn(model),
          ),
        ],
        children: [
          if (model.isLoading && model.snapshot == null)
            const Center(child: CupertinoActivityIndicator()),
          if (model.errorMessage != null)
            _NoticeCard(
              key: const ValueKey('body-error'),
              message: model.errorMessage!,
            ),
          GainerGroupedSection(
            header: 'Aktives Ziel',
            children: _goalRows(model),
          ),
          const SizedBox(height: GainerSpacing.m),
          GainerGroupedSection(header: 'Heute', children: _todayRows(model)),
          const SizedBox(height: GainerSpacing.l),
          const GainerSectionHeader(title: 'Verlauf'),
          const SizedBox(height: GainerSpacing.xs),
          _history(model.snapshot, isLoading: model.isLoading),
        ],
      ),
    ),
  );

  List<Widget> _goalRows(BodyViewModel model) {
    final snapshot = model.snapshot;
    if (snapshot == null) {
      return [
        GainerListRow(
          title: model.isLoading
              ? 'Zieldaten werden geladen …'
              : 'Zieldaten sind nicht verfügbar.',
        ),
      ];
    }
    final goal = snapshot.activeGoal?.value;
    if (goal == null) {
      return [
        GainerListRow(
          key: const ValueKey('body-open-goal'),
          title: 'Körperziel festlegen',
          leadingIcon: CupertinoIcons.scope,
          showChevron: true,
          onTap: () => _openGoal(model),
        ),
      ];
    }
    return [
      GainerListRow(
        key: const ValueKey('body-open-goal'),
        title: _goalLabel(goal.kind),
        subtitle:
            '${_formatWeight(goal.startWeightKg)}  →  ${_formatWeight(goal.targetWeightKg)}',
        leadingIcon: CupertinoIcons.scope,
        showChevron: true,
        onTap: () => _openGoal(model),
      ),
      if (goal.targetDate case final date?)
        GainerListRow(title: 'Zieldatum', value: _prettyDate(date)),
    ];
  }

  List<Widget> _todayRows(BodyViewModel model) {
    final snapshot = model.snapshot;
    if (snapshot == null) {
      return [
        GainerListRow(
          title: model.isLoading
              ? 'Check-in wird geladen …'
              : 'Check-in konnte nicht geladen werden.',
        ),
      ];
    }
    final today = _dateOnly(DateTime.now());
    final entry = snapshot.checkIns
        .where((item) => item.value.localDate == today)
        .firstOrNull
        ?.value;
    if (entry == null) {
      return const [GainerListRow(title: 'Noch kein Check-in für heute')];
    }
    return [
      GainerListRow(title: 'Gewicht', value: _formatWeight(entry.weightKg)),
      if (entry.caloriesKcal case final calories?)
        GainerListRow(
          title: 'Kalorien',
          value: '${calories.toStringAsFixed(0)} kcal',
        ),
      if (entry.steps case final steps?)
        GainerListRow(title: 'Schritte', value: steps.toString()),
    ];
  }

  Widget _history(BodyTrackingSnapshot? snapshot, {required bool isLoading}) {
    if (snapshot == null) {
      return GainerGroupedSection(
        children: const [GainerListRow(title: 'Verlauf wird geladen …')],
      );
    }
    final entries = snapshot.checkIns;
    final goals = snapshot.goalHistory;
    if (entries.isEmpty && goals.isEmpty) {
      return GainerGroupedSection(
        footer: isLoading ? null : 'Deine Einträge erscheinen hier, sobald du deinen ersten Check-in gespeichert hast.',
        children: [
          GainerListRow(
            title: isLoading ? 'Verlauf wird geladen …' : 'Noch keine Einträge',
          ),
        ],
      );
    }
    return GainerGroupedSection(
      children: [
        for (final item in goals)
          GainerListRow(
            title:
                '${_goalLabel(item.value.kind)} · ${_prettyDate(item.value.startDate)}',
            subtitle:
                '${_formatWeight(item.value.startWeightKg)} → ${_formatWeight(item.value.targetWeightKg)}',
          ),
        if (entries.isEmpty)
          const GainerListRow(title: 'Noch keine Check-ins gespeichert.'),
        for (final item in entries.take(10))
          GainerListRow(
            title: _prettyDate(item.value.localDate),
            value: _formatWeight(item.value.weightKg),
          ),
      ],
    );
  }

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

  /// Formular-Sheet für Ziel oder Check-in; „Sichern“ ist die Abschlussaktion.
  /// Ohne feste Höhe: das Sheet passt sich dem Inhalt an und scrollt bei Bedarf.
  Future<void> _showEditor(
    BodyViewModel model, {
    required bool goal,
  }) => showGainerSheet<void>(
    context: context,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: model,
      child: Consumer<BodyViewModel>(
        builder: (sheetContext, liveModel, _) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final error = liveModel.errorMessage;
            final errors = _fieldErrors(error);
            final rowKeys = goal ? _goalFieldKeys : _checkInFieldKeys;
            // Feldfehler stehen direkt an der Zeile, alles andere als Hinweis.
            final notice = errors.isNotEmpty && rowKeys.containsAll(errors.keys)
                ? null
                : error;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GainerSheetHeader(
                  title: goal ? 'Körperziel' : _checkInTitle,
                  trailing: GainerPillButton(
                    key: ValueKey(
                      goal ? 'body-save-goal' : 'body-save-checkin',
                    ),
                    label: 'Sichern',
                    isLoading: liveModel.isSaving,
                    onPressed: liveModel.isSaving
                        ? null
                        : () => _saveFromSheet(
                            sheetContext,
                            liveModel,
                            goal: goal,
                          ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      GainerSpacing.m,
                      GainerSpacing.s,
                      GainerSpacing.m,
                      GainerSpacing.l +
                          MediaQuery.viewInsetsOf(sheetContext).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (notice case final message?)
                          _NoticeCard(message: message),
                        _editorFields(
                          sheetContext,
                          liveModel,
                          goal: goal,
                          rebuild: setSheetState,
                          errors: errors,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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

  Widget _editorFields(
    BuildContext context,
    BodyViewModel model, {
    required bool goal,
    required StateSetter rebuild,
    required Map<String, String> errors,
  }) {
    final unitLabel = _unit == BodyWeightUnit.kilograms ? 'kg' : 'lb';
    if (goal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GainerSegmentedControl<BodyGoalKind>(
            value: _kind,
            options: const {
              BodyGoalKind.bulk: 'Aufbau',
              BodyGoalKind.maintain: 'Halten',
              BodyGoalKind.cut: 'Abnehmen',
            },
            onChanged: (value) => rebuild(() => _kind = value),
          ),
          const SizedBox(height: GainerSpacing.m),
          GainerGroupedSection(
            header: 'Gewicht',
            children: [
              GainerListRow(
                title: 'Einheit',
                trailing: SizedBox(
                  width: 120,
                  child: GainerSegmentedControl<BodyWeightUnit>(
                    key: const ValueKey('body-goal-weight-unit'),
                    value: _unit,
                    options: const {
                      BodyWeightUnit.kilograms: 'kg',
                      BodyWeightUnit.pounds: 'lb',
                    },
                    onChanged: (value) => rebuild(() => _changeUnit(value)),
                  ),
                ),
              ),
              _numberRow(
                'Startgewicht',
                _startWeight,
                unit: unitLabel,
                errorText: errors['startWeightKg'],
                fieldKey: const ValueKey('body-start-weight'),
              ),
              _numberRow(
                'Zielgewicht',
                _targetWeight,
                unit: unitLabel,
                errorText: errors['targetWeightKg'],
                fieldKey: const ValueKey('body-target-weight'),
              ),
            ],
          ),
          const SizedBox(height: GainerSpacing.m),
          GainerGroupedSection(
            header: 'Zeitraum',
            footer: 'Das Zieldatum ist optional.',
            children: [
              GainerDateRow(
                key: const ValueKey('body-start-date'),
                title: 'Startdatum',
                value: _startDate,
                format: _prettyDateTime,
                onChanged: (picked) => rebuild(() => _startDate = picked),
              ),
              // Langes Drücken entfernt das Zieldatum über ein Kontext-Sheet.
              GestureDetector(
                onLongPress: _targetDate == null
                    ? null
                    : () => _targetDateActions(rebuild),
                child: GainerListRow(
                  key: const ValueKey('body-target-date'),
                  title: 'Zieldatum',
                  value: _targetDate == null
                      ? 'Kein Datum'
                      : _prettyDateTime(_targetDate!),
                  showChevron: true,
                  onTap: () => _pickTargetDate(rebuild),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerGroupedSection(
          children: [
            GainerDateRow(
              key: const ValueKey('body-checkin-date'),
              title: 'Datum',
              value: _checkInDate,
              format: _prettyDateTime,
              maximum: DateTime.now(),
              onChanged: model.isSaving
                  ? null
                  : (picked) => rebuild(() {
                      _checkInDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                      _prefillCheckIn(model, _checkInDate);
                    }),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          header: 'Messwerte',
          footer: 'Gewicht ist erforderlich. Weitere Angaben sind optional.',
          children: [
            _numberRow(
              'Gewicht',
              _checkInWeight,
              unit: unitLabel,
              errorText: errors['weightKg'],
              fieldKey: const ValueKey('body-checkin-weight'),
            ),
            _numberRow(
              'Kalorien',
              _calories,
              unit: 'kcal',
              errorText: errors['caloriesKcal'],
            ),
            _numberRow(
              'Protein',
              _protein,
              unit: 'g',
              errorText: errors['proteinGrams'],
            ),
            _numberRow(
              'Kohlenhydrate',
              _carbs,
              unit: 'g',
              errorText: errors['carbohydrateGrams'],
            ),
            _numberRow('Fett', _fat, unit: 'g', errorText: errors['fatGrams']),
            _numberRow(
              'Schritte',
              _steps,
              decimal: false,
              errorText: errors['steps'],
            ),
            _numberRow(
              'Schlaf',
              _sleep,
              unit: 'min',
              decimal: false,
              errorText: errors['sleepMinutes'],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _targetDateActions(StateSetter rebuild) async {
    final action = await showGainerActionSheet<bool>(
      context: context,
      title: 'Zieldatum',
      groups: const [
        [
          GainerSheetAction(
            label: 'Datum entfernen',
            icon: CupertinoIcons.trash,
            value: true,
            destructive: true,
          ),
        ],
      ],
    );
    if (action == true && mounted) {
      rebuild(() => _targetDate = null);
    }
  }

  Future<void> _pickTargetDate(StateSetter rebuild) async {
    final picked = await showGainerDatePicker(
      context: context,
      title: 'Zieldatum',
      initial: _targetDate ?? _startDate,
    );
    if (picked != null && mounted) {
      rebuild(() => _targetDate = picked);
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

  /// Datum im Format „3. Okt 2026“ für Zeilen und Sheets.
  String _prettyDateTime(DateTime date) => _prettyDate(_dateOnly(date));

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

  String _goalLabel(BodyGoalKind kind) => switch (kind) {
    BodyGoalKind.bulk => 'Muskelaufbau',
    BodyGoalKind.maintain => 'Gewicht halten',
    BodyGoalKind.cut => 'Gewicht reduzieren',
  };

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

Widget _numberRow(
  String label,
  TextEditingController controller, {
  String? unit,
  String? errorText,
  bool decimal = true,
  Key? fieldKey,
}) => GainerTextFieldRow(
  label: label,
  controller: controller,
  placeholder: 'Eintragen',
  unit: unit,
  keyboardType: TextInputType.numberWithOptions(decimal: decimal),
  errorText: errorText,
  fieldKey: fieldKey,
);

/// Feldfehler aus der Validierung des ViewModels, z. B. `weightKg: Das Gewicht
/// muss positiv sein.`. Andere Fehler liefern keine Felder.
Map<String, String> _fieldErrors(String? message) {
  if (message == null ||
      !message.startsWith('BodyTrackingValidationException(')) {
    return const {};
  }
  return {
    for (final match in RegExp(r'(\w+): ([^,}]+)').allMatches(message))
      match.group(1)!: match.group(2)!.trim(),
  };
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
