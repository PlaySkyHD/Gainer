import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'body_view_model.dart';
import 'check_in_format.dart';

const _checkInTitle = 'Check-in';

const _goalFieldKeys = {'startWeightKg', 'targetWeightKg'};
const _checkInFieldKeys = {'weightKg', 'steps', 'sleepMinutes'};

/// Vorschlag für den Zeit-Picker, solange nichts gesetzt ist.
const _defaultBedMinutes = 23 * 60;
const _defaultWakeMinutes = 7 * 60;

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
  BodyGoalKind _kind = BodyGoalKind.maintain;
  BodyWeightUnit _unit = BodyWeightUnit.kilograms;
  DateTime _startDate = DateTime.now();
  DateTime? _targetDate;
  DateTime _checkInDate = DateTime.now();

  // Schlaf als Minuten seit Mitternacht; null = nicht gesetzt.
  int? _bedMinutes;
  int? _wakeMinutes;
  int? _existingSleepMinutes;
  bool _sleepFromHealth = false;
  String? _healthWeightText;
  int _healthToken = 0;
  StateSetter? _sheetSetState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.load(),
    );
  }

  @override
  void dispose() {
    for (final controller in [_startWeight, _targetWeight, _checkInWeight]) {
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
        GainerListRow(title: 'Schritte', value: formatStepCount(steps)),
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
    unawaited(_loadHealth(model, _checkInDate));
    await _showEditor(model, goal: false);
  }

  DailyCheckIn? _checkInFor(BodyViewModel model, String localDate) => model
      .snapshot
      ?.checkIns
      .where((item) => item.value.localDate == localDate)
      .firstOrNull
      ?.value;

  /// Füllt Gewicht und Schlaf aus Apple Health vor, ohne Eingaben zu überschreiben.
  Future<void> _loadHealth(BodyViewModel model, DateTime date) async {
    final token = ++_healthToken;
    final loaded = await model.loadCheckInHealth(_dateOnly(date));
    if (loaded == null || !mounted || token != _healthToken) return;
    if (_checkInWeight.text.trim().isEmpty && loaded.weightKg != null) {
      final text = _editableWeight(weightForDisplay(loaded.weightKg!, _unit));
      _checkInWeight.text = text;
      _healthWeightText = text;
    }
    if (_bedMinutes == null && _wakeMinutes == null && loaded.sleep != null) {
      final bed = loaded.sleep!.bedtimeUtc.toLocal();
      final wake = loaded.sleep!.wakeUtc.toLocal();
      _bedMinutes = bed.hour * 60 + bed.minute;
      _wakeMinutes = wake.hour * 60 + wake.minute;
      _sleepFromHealth = true;
    }
    _sheetSetState?.call(() {});
  }

  void _prefillCheckIn(BodyViewModel model, DateTime date) {
    final existing = _checkInFor(model, _dateOnly(date));
    _checkInWeight.text = existing == null
        ? ''
        : _editableWeight(weightForDisplay(existing.weightKg, _unit));
    _healthWeightText = null;
    _bedMinutes = null;
    _wakeMinutes = null;
    _existingSleepMinutes = existing?.sleepMinutes;
    _sleepFromHealth = false;
  }

  /// Formular-Sheet für Ziel oder Check-in; „Sichern“ ist die Abschlussaktion.
  /// Ohne feste Höhe: das Sheet passt sich dem Inhalt an und scrollt bei Bedarf.
  Future<void> _showEditor(BodyViewModel model, {required bool goal}) async {
    try {
      await _presentEditor(model, goal: goal);
    } finally {
      _sheetSetState = null;
      _healthToken++;
    }
  }

  Future<void> _presentEditor(
    BodyViewModel model, {
    required bool goal,
  }) => showGainerSheet<void>(
    context: context,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: model,
      child: Consumer<BodyViewModel>(
        builder: (sheetContext, liveModel, _) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            if (!goal) _sheetSetState = setSheetState;
            final errors = liveModel.fieldErrors;
            final rowKeys = goal ? _goalFieldKeys : _checkInFieldKeys;
            // Feldfehler stehen direkt an der Zeile, alles andere als Hinweis.
            final unmatched = [
              for (final entry in errors.entries)
                if (!rowKeys.contains(entry.key)) entry.value,
            ];
            final notice =
                liveModel.errorMessage ??
                (unmatched.isEmpty ? null : unmatched.join('\n'));
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
                      GainerSpacing.l,
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
        liveModel.fieldErrors.isEmpty &&
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
                      unawaited(_loadHealth(model, _checkInDate));
                    }),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        ListenableBuilder(
          listenable: _checkInWeight,
          builder: (context, _) => GainerGroupedSection(
            header: 'Gewicht',
            footer:
                _healthWeightText != null &&
                    _checkInWeight.text == _healthWeightText
                ? 'Gewicht aus Apple Health'
                : 'Gewicht ist erforderlich.',
            children: [
              _numberRow(
                'Gewicht',
                _checkInWeight,
                unit: unitLabel,
                errorText: errors['weightKg'],
                fieldKey: const ValueKey('body-checkin-weight'),
              ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.m),
        ..._sleepSection(rebuild, errors['sleepMinutes']),
        const SizedBox(height: GainerSpacing.m),
        ..._stepsSection(model, errors['steps']),
      ],
    );
  }

  List<Widget> _sleepSection(StateSetter rebuild, String? errorText) {
    final bed = _bedMinutes;
    final wake = _wakeMinutes;
    final duration = bed != null && wake != null
        ? sleepMinutesBetween(bed, wake)
        : (bed == null && wake == null ? _existingSleepMinutes : null);
    return [
      GainerGroupedSection(
        header: 'Schlaf',
        footer:
            errorText ?? (_sleepFromHealth ? 'Schlaf aus Apple Health' : null),
        children: [
          _timeRow(
            'Zu Bett',
            const ValueKey('body-checkin-bedtime'),
            bed,
            _defaultBedMinutes,
            (minutes) => rebuild(() {
              _bedMinutes = minutes;
              _sleepFromHealth = false;
            }),
          ),
          _timeRow(
            'Aufgestanden',
            const ValueKey('body-checkin-wake'),
            wake,
            _defaultWakeMinutes,
            (minutes) => rebuild(() {
              _wakeMinutes = minutes;
              _sleepFromHealth = false;
            }),
          ),
          GainerListRow(
            key: const ValueKey('body-checkin-sleep-duration'),
            title: 'Dauer',
            value: duration == null ? '–' : formatSleepDuration(duration),
          ),
        ],
      ),
    ];
  }

  Widget _timeRow(
    String title,
    Key key,
    int? minutes,
    int fallback,
    ValueChanged<int> onChanged,
  ) => GainerDateRow(
    key: key,
    title: title,
    mode: CupertinoDatePickerMode.time,
    value: _timeOfDay(minutes ?? fallback),
    format: (_) =>
        minutes == null ? 'Nicht gesetzt' : formatMinuteOfDay(minutes),
    onChanged: (picked) => onChanged(picked.hour * 60 + picked.minute),
  );

  DateTime _timeOfDay(int minutes) =>
      DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60);

  List<Widget> _stepsSection(BodyViewModel model, String? errorText) {
    final steps =
        model.checkInHealth?.steps ??
        _checkInFor(model, _dateOnly(_checkInDate))?.steps;
    return [
      GainerGroupedSection(
        header: 'Schritte',
        footer:
            errorText ??
            (steps == null
                ? 'Erlaube Gainer in Apple Health den Zugriff auf Schritte, dann erscheinen sie hier.'
                : null),
        children: [
          steps == null
              ? const GainerListRow(
                  key: ValueKey('body-checkin-steps'),
                  title: 'Schritte',
                  subtitle: 'Keine Daten aus Apple Health',
                )
              : GainerListRow(
                  key: const ValueKey('body-checkin-steps'),
                  title: 'Schritte',
                  value: formatStepCount(steps),
                ),
        ],
      ),
    ];
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
    final bed = _bedMinutes;
    final wake = _wakeMinutes;
    final hasSleepTimes = bed != null && wake != null;
    final sleepMinutes = hasSleepTimes
        ? sleepMinutesBetween(bed, wake)
        : _existingSleepMinutes;
    // Aufgestanden liegt am Check-in-Tag, Zu Bett davor (ggf. vor Mitternacht).
    final wakeAt = hasSleepTimes
        ? DateTime(
            _checkInDate.year,
            _checkInDate.month,
            _checkInDate.day,
            wake ~/ 60,
            wake % 60,
          )
        : null;
    await model.saveCheckIn(
      localDate: _dateOnly(_checkInDate),
      weightKg: weightToKilograms(
        _parseEditableDouble(_checkInWeight) ?? double.nan,
        _unit,
      ),
      sleepMinutes: sleepMinutes,
      bedtime: wakeAt?.subtract(Duration(minutes: sleepMinutes!)),
      wake: wakeAt,
    );
  }

  double? _parseEditableDouble(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  String _formatWeight(double kilograms) =>
      '${weightForDisplay(kilograms, _unit).toStringAsFixed(1).replaceAll('.', ',')} ${_unit == BodyWeightUnit.kilograms ? 'kg' : 'lb'}';

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

  String _editableWeight(double value) {
    final text = value.toStringAsFixed(6);
    final trimmed = text.replaceFirst(RegExp(r'\.?0+$'), '');
    final withDecimal = trimmed.contains('.') ? trimmed : '$trimmed.0';
    return withDecimal.replaceAll('.', ',');
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
