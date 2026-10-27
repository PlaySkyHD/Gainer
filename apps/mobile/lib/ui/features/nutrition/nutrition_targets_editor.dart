import 'package:flutter/cupertino.dart';

import '../../../domain/models/nutrition/nutrition.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'nutrition_averages_view.dart';

/// Eingaben des Ziel-Editors.
typedef NutritionTargetsInput = ({
  NutritionDayTarget training,
  NutritionDayTarget? restDay,
  double? saltGrams,
  double? fiberGrams,
});

/// Speichert die Ziele; liefert null bei Erfolg, sonst die Fehlermeldung.
typedef NutritionTargetsSave = Future<String?> Function(
  NutritionTargetsInput input,
);

/// Öffnet den Editor für die Ziele. Gelingt [onSave], schließt das Sheet;
/// sonst bleibt es mit den Eingaben offen und zeigt den Fehler.
Future<void> showNutritionTargetsEditor(
  BuildContext context, {
  required NutritionTargetVersion? current,
  required bool hasSchedule,
  required NutritionTargetsSave onSave,
  VoidCallback? onSetUpSchedule,
}) => showGainerSheet<void>(
  context: context,
  heightFactor: 0.92,
  builder: (_) => NutritionTargetsEditor(
    current: current,
    hasSchedule: hasSchedule,
    onSetUpSchedule: onSetUpSchedule,
    onSave: onSave,
  ),
);

/// Inhalt des Ziel-Editors; öffentlich für Tests und Vorschauen.
class NutritionTargetsEditor extends StatefulWidget {
  const NutritionTargetsEditor({
    required this.current,
    required this.hasSchedule,
    this.onSetUpSchedule,
    this.onSave,
    super.key,
  });

  final NutritionTargetVersion? current;
  final bool hasSchedule;
  final VoidCallback? onSetUpSchedule;

  /// Speichert die Eingaben. Ohne [onSave] schließt das Sheet mit den
  /// Eingaben als Ergebnis.
  final NutritionTargetsSave? onSave;

  @override
  State<NutritionTargetsEditor> createState() => _NutritionTargetsEditorState();
}

class _NutritionTargetsEditorState extends State<NutritionTargetsEditor> {
  late final _DayTargetFields _training = _DayTargetFields(
    widget.current?.trainingDay,
  );
  late final _DayTargetFields _rest = _DayTargetFields(
    widget.current?.restDay ?? widget.current?.trainingDay,
  );
  late bool _restEnabled = widget.current?.restDay != null;
  late final _salt = TextEditingController(
    text: _plain(
      widget.current?.effectiveSaltGrams ??
          NutritionTargetVersion.defaultSaltGrams,
    ),
  );
  bool _saving = false;
  String? _saveError;
  late final _fiber = TextEditingController(
    text: _plain(
      widget.current?.effectiveFiberGrams ??
          NutritionTargetVersion.defaultFiberGrams,
    ),
  );

  @override
  void dispose() {
    _training.dispose();
    _rest.dispose();
    _salt.dispose();
    _fiber.dispose();
    super.dispose();
  }

  double? get _saltValue {
    final text = _salt.text.trim();
    if (text.isEmpty) return null;
    return _parse(text);
  }

  bool get _saltValid {
    if (_salt.text.trim().isEmpty) return true;
    final value = _saltValue;
    return value != null && value > 0 && value <= 100;
  }

  double? get _fiberValue {
    final text = _fiber.text.trim();
    if (text.isEmpty) return null;
    return _parse(text);
  }

  bool get _fiberValid {
    if (_fiber.text.trim().isEmpty) return true;
    final value = _fiberValue;
    return value != null && value > 0 && value <= 100;
  }

  bool get _canSave =>
      _training.target != null &&
      (!_restEnabled || _rest.target != null) &&
      _saltValid &&
      _fiberValid;

  Future<void> _save() async {
    final training = _training.target;
    if (training == null) return;
    final salt = _saltValue;
    // Der unveränderte Standardwert bleibt offen, damit die Grenze dem
    // Standard folgt.
    final keepDefault =
        widget.current?.saltGrams == null &&
        salt == NutritionTargetVersion.defaultSaltGrams;
    final fiber = _fiberValue;
    final keepFiberDefault =
        widget.current?.fiberGrams == null &&
        fiber == NutritionTargetVersion.defaultFiberGrams;
    final input = (
      training: training,
      restDay: _restEnabled ? _rest.target : null,
      saltGrams: keepDefault ? null : salt,
      fiberGrams: keepFiberDefault ? null : fiber,
    );
    final onSave = widget.onSave;
    if (onSave == null) {
      Navigator.of(context).pop<NutritionTargetsInput>(input);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final error = await onSave(input);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _saveError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      children: [
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
                key: const ValueKey('nutrition-targets-close'),
                icon: CupertinoIcons.xmark,
                semanticLabel: 'Schließen',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Ziele',
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ),
              GainerPillButton(
                key: const ValueKey('nutrition-targets-save'),
                label: 'Sichern',
                isLoading: _saving,
                onPressed: _canSave && !_saving ? _save : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              GainerSpacing.m,
              GainerSpacing.m,
              GainerSpacing.l,
            ),
            children: [
              if (_saveError case final message?)
                Padding(
                  padding: const EdgeInsets.only(bottom: GainerSpacing.s),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      key: const ValueKey('nutrition-targets-save-error'),
                      style: GainerTypography.body.copyWith(
                        color: colors.destructive,
                      ),
                    ),
                  ),
                ),
              ..._targetGroup(
                title: _restEnabled ? 'Trainingstag' : 'Ziel pro Tag',
                fields: _training,
                keyPrefix: 'training',
              ),
              const SizedBox(height: GainerSpacing.l),
              GainerGroupedSection(
                footer: widget.hasSchedule
                    ? 'Trainingstage kommen aus deinem Rhythmus und deinen Trainings.'
                    : 'Trainingstage kommen aus deinem Rhythmus. Ohne Rhythmus zählt nur ein Tag mit beendetem Training.',
                children: [
                  GainerListRow(
                    title: 'Eigenes Ziel für Ruhetage',
                    leadingIcon: CupertinoIcons.moon,
                    trailing: CupertinoSwitch(
                      key: const ValueKey('nutrition-targets-rest-switch'),
                      value: _restEnabled,
                      onChanged: (value) =>
                          setState(() => _restEnabled = value),
                    ),
                  ),
                  if (!widget.hasSchedule && widget.onSetUpSchedule != null)
                    GainerListRow(
                      key: const ValueKey('nutrition-targets-setup-schedule'),
                      title: 'Rhythmus einrichten',
                      leadingIcon: CupertinoIcons.calendar,
                      showChevron: true,
                      onTap: widget.onSetUpSchedule,
                    ),
                ],
              ),
              if (_restEnabled) ...[
                const SizedBox(height: GainerSpacing.l),
                ..._targetGroup(
                  title: 'Ruhetag',
                  fields: _rest,
                  keyPrefix: 'rest',
                ),
              ],
              const SizedBox(height: GainerSpacing.l),
              GainerGroupedSection(
                footer: _fiberValid
                    ? 'Mindestens pro Tag, für Trainings- und Ruhetage. Die DGE empfiehlt mindestens 30 g.'
                    : 'Das Ballaststoffziel muss zwischen 0 und 100 g liegen.',
                children: [
                  GainerTextFieldRow(
                    label: 'Ballaststoffe mindestens',
                    unit: 'g',
                    controller: _fiber,
                    keyboardType: _decimalKeyboard,
                    fieldKey: const ValueKey('nutrition-target-fiber'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.l),
              GainerGroupedSection(
                footer: _saltValid
                    ? 'Obergrenze pro Tag, für Trainings- und Ruhetage. Die DGE empfiehlt höchstens 6 g.'
                    : 'Die Salzgrenze muss zwischen 0 und 100 g liegen.',
                children: [
                  GainerTextFieldRow(
                    label: 'Salz höchstens',
                    unit: 'g',
                    controller: _salt,
                    keyboardType: _decimalKeyboard,
                    fieldKey: const ValueKey('nutrition-target-salt'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.m),
              Text(
                'Änderungen gelten ab heute. Vergangene Tage behalten ihr Ziel.',
                textAlign: TextAlign.center,
                style: GainerTypography.caption.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _targetGroup({
    required String title,
    required _DayTargetFields fields,
    required String keyPrefix,
  }) {
    final percent = fields.mode == NutritionTargetInputMode.percent;
    final unit = percent ? '%' : 'g';
    return [
      GainerSectionHeader(title: title),
      const SizedBox(height: GainerSpacing.xs),
      GainerSegmentedControl<NutritionTargetInputMode>(
        key: ValueKey('nutrition-targets-$keyPrefix-mode'),
        options: const {
          NutritionTargetInputMode.grams: 'Gramm',
          NutritionTargetInputMode.percent: 'Prozent',
        },
        value: fields.mode,
        onChanged: (mode) => setState(() => fields.switchMode(mode)),
      ),
      const SizedBox(height: GainerSpacing.s),
      GainerGroupedSection(
        footer: fields.footer,
        children: [
          GainerTextFieldRow(
            label: 'Kalorien',
            unit: 'kcal',
            controller: fields.kcal,
            keyboardType: _decimalKeyboard,
            fieldKey: ValueKey('nutrition-targets-$keyPrefix-kcal'),
            onChanged: (_) => setState(() {}),
          ),
          GainerTextFieldRow(
            label: 'Protein',
            unit: unit,
            controller: fields.protein,
            keyboardType: _decimalKeyboard,
            fieldKey: ValueKey('nutrition-targets-$keyPrefix-protein'),
            onChanged: (_) => setState(() {}),
          ),
          GainerTextFieldRow(
            label: 'Kohlenhydrate',
            unit: unit,
            controller: fields.carbs,
            keyboardType: _decimalKeyboard,
            fieldKey: ValueKey('nutrition-targets-$keyPrefix-carbs'),
            onChanged: (_) => setState(() {}),
          ),
          GainerTextFieldRow(
            label: 'Fett',
            unit: unit,
            controller: fields.fat,
            keyboardType: _decimalKeyboard,
            fieldKey: ValueKey('nutrition-targets-$keyPrefix-fat'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ];
  }
}

/// Eingabefelder eines Tagesziels mit Umrechnung zwischen Gramm und Prozent.
class _DayTargetFields {
  _DayTargetFields(NutritionDayTarget? initial)
    : mode = initial?.inputMode ?? NutritionTargetInputMode.percent,
      kcal = TextEditingController(text: _plain(initial?.kilocalories ?? 2000)),
      protein = TextEditingController(),
      carbs = TextEditingController(),
      fat = TextEditingController() {
    if (initial == null) {
      protein.text = '25';
      carbs.text = '50';
      fat.text = '25';
    } else if (mode == NutritionTargetInputMode.percent) {
      protein.text = _plain(initial.proteinPercent ?? 0);
      carbs.text = _plain(initial.carbohydratePercent ?? 0);
      fat.text = _plain(initial.fatPercent ?? 0);
    } else {
      protein.text = _plain(initial.proteinGrams);
      carbs.text = _plain(initial.carbohydrateGrams);
      fat.text = _plain(initial.fatGrams);
    }
  }

  NutritionTargetInputMode mode;
  final TextEditingController kcal, protein, carbs, fat;

  /// Gültiges Ziel oder null.
  NutritionDayTarget? get target {
    final values = [kcal, protein, carbs, fat].map((c) => _parse(c.text));
    if (values.any((value) => value == null)) return null;
    final [k, p, c, f] = values.cast<double>().toList();
    final NutritionDayTarget value;
    if (mode == NutritionTargetInputMode.percent) {
      if ((p + c + f - 100).abs() > 0.01 || k <= 0) return null;
      final grams = macroGramsFromPercent(
        kilocalories: k,
        proteinPercent: p,
        carbohydratePercent: c,
        fatPercent: f,
      );
      value = NutritionDayTarget(
        inputMode: mode,
        kilocalories: k,
        proteinGrams: grams.proteinGrams!,
        carbohydrateGrams: grams.carbohydrateGrams!,
        fatGrams: grams.fatGrams!,
        proteinPercent: p,
        carbohydratePercent: c,
        fatPercent: f,
      );
    } else {
      value = NutritionDayTarget(
        inputMode: mode,
        kilocalories: k,
        proteinGrams: p,
        carbohydrateGrams: c,
        fatGrams: f,
      );
    }
    return validateDayTarget(value).isEmpty ? value : null;
  }

  /// Fehler oder Hinweis unter den Eingaben.
  String? get footer {
    final values = [kcal, protein, carbs, fat].map((c) => _parse(c.text));
    if (values.any((value) => value == null || value < 0)) {
      return 'Bitte alle Werte als Zahl eingeben.';
    }
    final [k, p, c, f] = values.cast<double>().toList();
    if (k <= 0) return 'Die Kalorien müssen größer als 0 sein.';
    if (mode == NutritionTargetInputMode.percent) {
      final sum = p + c + f;
      return (sum - 100).abs() > 0.01
          ? 'Makroanteile müssen zusammen 100 % ergeben (jetzt ${formatNutritionNumber(sum, decimals: 1)} %).'
          : 'Gramm werden mit 4/4/9 kcal berechnet.';
    }
    final energy = p * 4 + c * 4 + f * 9;
    return 'Aus den Makros: ${formatNutritionNumber(energy)} kcal.';
  }

  /// Wechselt die Eingabe und rechnet die Werte um, damit nichts verloren geht.
  void switchMode(NutritionTargetInputMode next) {
    if (next == mode) return;
    final k = _parse(kcal.text);
    final values = [protein, carbs, fat].map((c) => _parse(c.text)).toList();
    mode = next;
    if (k == null || k <= 0 || values.any((value) => value == null)) return;
    const factors = [4.0, 4.0, 9.0];
    for (var index = 0; index < 3; index++) {
      final controller = [protein, carbs, fat][index];
      final value = values[index]!;
      controller.text = next == NutritionTargetInputMode.percent
          ? _plain(roundNutrition(value * factors[index] / k * 100))
          : _plain(roundNutrition(k * value / 100 / factors[index]));
    }
  }

  void dispose() {
    for (final controller in [kcal, protein, carbs, fat]) {
      controller.dispose();
    }
  }
}

const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

double? _parse(String input) =>
    double.tryParse(input.trim().replaceAll(',', '.'));

/// Eingabewert ohne Tausenderpunkt, mit Komma und ohne Nullen am Ende. Auch für
/// vorbefüllte Felder anderer Nutzer-Eingaben (z. B. Menge in Gramm).
String plainNumberInput(double value) => _plain(value);

String _plain(double value) => value
    .toStringAsFixed(2)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');
