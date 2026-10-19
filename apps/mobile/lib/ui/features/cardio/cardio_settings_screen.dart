import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/cardio/cardio_preferences.dart';
import '../../../domain/models/cardio/cardio_zones.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'cardio_feature.dart';
import 'cardio_hrv_measurement_screen.dart';
import 'cardio_template_screens.dart';
import 'cardio_warmup_picker.dart';

Future<void> openCardioSettings(
  BuildContext context, {
  required CardioPreferences preferences,
  CardioFeature? feature,
}) {
  return Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) =>
          CardioSettingsScreen(preferences: preferences, feature: feature),
    ),
  );
}

/// Einstellungen für Cardio: Maximalpuls, Alter, Ruhepuls, Alarm, Aufwärmzeit
/// und die daraus berechneten Zonen. Änderungen gelten sofort.
class CardioSettingsScreen extends StatefulWidget {
  const CardioSettingsScreen({
    required this.preferences,
    this.feature,
    super.key,
  });

  final CardioPreferences preferences;

  /// Mit Check-in und Gurt erscheint die Zeile „HRV-Messung“.
  final CardioFeature? feature;

  @override
  State<CardioSettingsScreen> createState() => _CardioSettingsScreenState();
}

class _CardioSettingsScreenState extends State<CardioSettingsScreen> {
  final _max = TextEditingController();
  final _age = TextEditingController();
  final _rest = TextEditingController();
  final _weekly = TextEditingController();
  final _errors = <String, String>{};

  CardioPreferences get _preferences => widget.preferences;

  @override
  void initState() {
    super.initState();
    _fill(_preferences.values.value);
    _preferences.read().then((values) {
      if (mounted) setState(() => _fill(values));
    });
  }

  void _fill(CardioPreferenceValues values) {
    _max.text = values.maxHeartRate?.toString() ?? '';
    _age.text = values.age?.toString() ?? '';
    _rest.text = values.restingHeartRate?.toString() ?? '';
    _weekly.text = values.weeklyTargetMinutes.toString();
  }

  @override
  void dispose() {
    _max.dispose();
    _age.dispose();
    _rest.dispose();
    _weekly.dispose();
    super.dispose();
  }

  /// Leer löscht den Wert, ein Wert im Bereich wird gespeichert, sonst
  /// erscheint ein Fehler und nichts wird geändert.
  void _numberChanged(
    String key,
    String text,
    int min,
    int max,
    CardioPreferenceValues Function(CardioPreferenceValues, int?) apply,
  ) {
    final trimmed = text.trim();
    final value = int.tryParse(trimmed);
    if (trimmed.isNotEmpty && (value == null || value < min || value > max)) {
      setState(() => _errors[key] = 'Erlaubt sind $min bis $max.');
      return;
    }
    setState(() => _errors.remove(key));
    _preferences.update((current) => apply(current, value));
  }

  @override
  Widget build(BuildContext context) {
    return GainerScaffold(
      title: 'Cardio',
      children: [
        ValueListenableBuilder<CardioPreferenceValues>(
          valueListenable: _preferences.values,
          builder: (context, values, _) => _content(values),
        ),
      ],
    );
  }

  Widget _content(CardioPreferenceValues values) {
    final estimate = values.age == null
        ? null
        : CardioZones.maxHeartRateFor(values.age!);
    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerGroupedSection(
          header: 'Puls',
          footer:
              'Ohne Maximalpuls schätzt Gainer ihn aus dem Alter. Mit Ruhepuls '
              'rechnen die Zonen nach Karvonen.',
          children: [
            GainerTextFieldRow(
              label: 'Maximalpuls',
              unit: 'bpm',
              controller: _max,
              fieldKey: const ValueKey('cardio-settings-max'),
              placeholder: estimate == null
                  ? 'optional'
                  : 'geschätzt $estimate',
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              errorText: _errors['max'],
              onChanged: (text) => _numberChanged(
                'max',
                text,
                100,
                250,
                (values, value) => values.copyWith(maxHeartRate: () => value),
              ),
            ),
            GainerTextFieldRow(
              label: 'Alter',
              unit: 'Jahre',
              controller: _age,
              fieldKey: const ValueKey('cardio-settings-age'),
              placeholder: 'optional',
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              errorText: _errors['age'],
              onChanged: (text) => _numberChanged(
                'age',
                text,
                10,
                100,
                (values, value) => values.copyWith(age: () => value),
              ),
            ),
            GainerTextFieldRow(
              label: 'Ruhepuls',
              unit: 'bpm',
              controller: _rest,
              fieldKey: const ValueKey('cardio-settings-rest'),
              placeholder: 'optional',
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              errorText: _errors['rest'],
              onChanged: (text) => _numberChanged(
                'rest',
                text,
                30,
                120,
                (values, value) =>
                    values.copyWith(restingHeartRate: () => value),
              ),
            ),
          ],
        ),
        if (widget.feature case final feature? when feature.body != null) ...[
          const SizedBox(height: GainerSpacing.l),
          GainerGroupedSection(
            header: 'Ruhe',
            footer:
                'Eine geführte Messung mit Pulsgurt liefert Ruhepuls und HRV '
                'für den Check-in.',
            children: [
              GainerListRow(
                key: const ValueKey('cardio-settings-hrv'),
                title: 'HRV-Messung',
                leadingIcon: CupertinoIcons.waveform_path_ecg,
                showChevron: true,
                onTap: () async {
                  await openHrvMeasurement(context, feature);
                  if (mounted) setState(() => _fill(_preferences.values.value));
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Einheit',
          footer:
              'Vorlagen teilen eine Einheit in Phasen mit wechselndem Ziel, '
              'z. B. 4×4. Nach dem Krafttraining bietet die Zusammenfassung '
              'an, direkt Cardio zu starten.',
          children: [
            GainerListRow(
              key: const ValueKey('cardio-settings-templates'),
              title: 'Vorlagen',
              value: '${values.allTemplates.length}',
              leadingIcon: CupertinoIcons.list_bullet,
              showChevron: true,
              onTap: () =>
                  openCardioTemplates(context, preferences: _preferences),
            ),
            GainerListRow(
              title: 'Cardio nach Krafttraining anbieten',
              trailing: CupertinoSwitch(
                key: const ValueKey('cardio-settings-offer'),
                value: values.offerAfterStrength,
                onChanged: (value) => _preferences.update(
                  (current) => current.copyWith(offerAfterStrength: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Wochenziel',
          footer:
              'Minuten pro Woche im Zielbereich (30 bis 600). Die Statistik '
              'zeigt dein Ziel als Linie.',
          children: [
            GainerTextFieldRow(
              label: 'Pro Woche',
              unit: 'min',
              controller: _weekly,
              fieldKey: const ValueKey('cardio-settings-weekly'),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              errorText: _errors['weekly'],
              onChanged: (text) {
                final value = int.tryParse(text.trim());
                if (value == null ||
                    value < CardioPreferenceValues.minWeeklyTargetMinutes ||
                    value > CardioPreferenceValues.maxWeeklyTargetMinutes) {
                  setState(
                    () => _errors['weekly'] =
                        'Erlaubt sind '
                        '${CardioPreferenceValues.minWeeklyTargetMinutes} bis '
                        '${CardioPreferenceValues.maxWeeklyTargetMinutes}.',
                  );
                  return;
                }
                setState(() => _errors.remove('weekly'));
                _preferences.update(
                  (current) => current.copyWith(weeklyTargetMinutes: value),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Alarm',
          footer:
              'Gainer meldet sich, wenn dein Puls nach der Aufwärmzeit länger '
              'außerhalb des Zielbereichs liegt.',
          children: [
            GainerListRow(
              title: 'Alarm bei Verlassen des Zielbereichs',
              trailing: CupertinoSwitch(
                key: const ValueKey('cardio-settings-alerts'),
                value: values.alertsEnabled,
                onChanged: (value) => _preferences.update(
                  (current) => current.copyWith(alertsEnabled: value),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Caption('Standard-Aufwärmzeit in Minuten'),
                  const SizedBox(height: GainerSpacing.xs),
                  CardioWarmupPicker(
                    seconds: values.warmupSeconds,
                    onChanged: (seconds) => _preferences.update(
                      (current) => current.copyWith(warmupSeconds: seconds),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Sprache',
          footer: values.voiceEnabled
              ? 'Gainer sagt Alarme und Phasenwechsel an. Musik wird dabei '
                    'leiser. Die Ansage erscheint zusätzlich zur '
                    'Benachrichtigung, die dann ohne Ton bleibt.'
              : 'Mit Sprachansagen hörst du Alarme und Phasenwechsel über '
                    'Kopfhörer, auch bei gesperrtem Display. Dann lässt sich '
                    'auch eine regelmäßige Ansage von Puls und Dauer wählen.',
          children: [
            GainerListRow(
              title: 'Sprachansagen',
              trailing: CupertinoSwitch(
                key: const ValueKey('cardio-settings-voice'),
                value: values.voiceEnabled,
                onChanged: (value) => _preferences.update(
                  (current) => current.copyWith(voiceEnabled: value),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Opacity(
                opacity: values.voiceEnabled ? 1 : 0.4,
                child: IgnorePointer(
                  key: const ValueKey('cardio-settings-voice-interval'),
                  ignoring: !values.voiceEnabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Caption('Regelmäßige Ansage in Minuten'),
                      const SizedBox(height: GainerSpacing.xs),
                      GainerSegmentedControl<int>(
                        options: {
                          for (final minutes
                              in CardioPreferenceValues.voiceIntervalOptions)
                            minutes: minutes == 0 ? 'Aus' : '$minutes',
                        },
                        value: values.voiceIntervalMinutes,
                        onChanged: (minutes) => _preferences.update(
                          (current) =>
                              current.copyWith(voiceIntervalMinutes: minutes),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        _zones(values),
      ],
    );
  }

  Widget _zones(CardioPreferenceValues values) {
    final zones = values.zones;
    if (zones.isEmpty) {
      return const GainerGroupedSection(
        header: 'Zonen',
        children: [
          Padding(
            padding: EdgeInsets.all(GainerSpacing.m),
            child: _Caption(
              'Gib Maximalpuls oder Alter an, dann zeigt Gainer hier die '
              'fünf Zonen.',
            ),
          ),
        ],
      );
    }
    return GainerGroupedSection(
      header: 'Zonen',
      children: [
        for (final zone in zones)
          GainerListRow(
            title: 'Zone ${zone.number}',
            value: '${zone.lowBpm}–${zone.highBpm} bpm',
          ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GainerTypography.label.copyWith(
        color: GainerDesign.colorsOf(context).secondaryText,
      ),
    );
  }
}
