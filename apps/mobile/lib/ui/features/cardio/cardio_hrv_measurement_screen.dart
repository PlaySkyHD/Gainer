import 'package:flutter/cupertino.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../data/repositories/cardio/cardio_preferences.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'cardio_feature.dart';
import 'cardio_format.dart';
import 'cardio_sensor_section.dart';
import 'hrv_measurement_controller.dart';

/// Öffnet die HRV-Messung. Voraussetzung: [CardioFeature.body] ist gesetzt.
Future<void> openHrvMeasurement(BuildContext context, CardioFeature feature) {
  return Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) => HrvMeasurementScreen(feature: feature),
    ),
  );
}

/// Geführte Ruhemessung mit Pulsgurt: 30 s Einschwingen, dann 1 bis 5 min
/// Messung. Ergebnis ist Ruhepuls (Median) und HRV (RMSSD) für den Check-in.
class HrvMeasurementScreen extends StatefulWidget {
  const HrvMeasurementScreen({
    required this.feature,
    this.controller,
    super.key,
  });

  final CardioFeature feature;

  /// Für Tests; sonst entsteht der Controller aus [feature].
  final HrvMeasurementController? controller;

  @override
  State<HrvMeasurementScreen> createState() => _HrvMeasurementScreenState();
}

class _HrvMeasurementScreenState extends State<HrvMeasurementScreen> {
  late final HrvMeasurementController _controller;
  late final bool _ownsController;
  bool _askedAboutNoise = false;
  bool _watching = false;
  String? _adoptMessage;

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    _ownsController = provided == null;
    final body = widget.feature.body;
    assert(
      provided != null || body != null,
      'HRV-Messung braucht den Check-in.',
    );
    _controller =
        provided ??
        HrvMeasurementController(
          platform: widget.feature.session.platform,
          session: widget.feature.session,
          body: body!,
          preferences: widget.feature.repository.preferences,
          trainingPreferences: widget.feature.session.trainingPreferences,
        );
    _controller.addListener(_onChanged);
    _controller.load();
    _watching = true;
    widget.feature.session.watch();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_watching) widget.feature.session.stopWatching();
    if (_ownsController) {
      _controller.dispose();
    } else {
      _controller.cancel();
    }
    super.dispose();
  }

  void _onChanged() {
    // Während der Messung liest der Controller selbst; sonst Gurtstatus lesen.
    if (_controller.isRunning && _watching) {
      _watching = false;
      widget.feature.session.stopWatching();
    } else if (!_controller.isRunning && !_watching) {
      _watching = true;
      widget.feature.session.watch();
    }
    if (_controller.phase != HrvPhase.result) _askedAboutNoise = false;
    final result = _controller.result;
    if (_controller.phase == HrvPhase.result &&
        result != null &&
        result.isNoisy &&
        result.isStorable &&
        !_askedAboutNoise) {
      _askedAboutNoise = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askNoisy());
    }
  }

  Future<void> _askNoisy() async {
    if (!mounted) return;
    final action = await showGainerStackedDialog<_NoisyAction>(
      context: context,
      title: 'Messung unruhig – wiederholen?',
      message:
          'Ein Teil der Herzschläge konnte nicht gewertet werden. Sitze oder '
          'liege ruhig und prüfe, ob der Gurt eng und feucht anliegt.',
      actions: const [
        GainerDialogAction(label: 'Wiederholen', value: _NoisyAction.repeat),
        GainerDialogAction(
          label: 'Trotzdem speichern',
          value: _NoisyAction.save,
        ),
      ],
    );
    if (!mounted) return;
    if (action == _NoisyAction.repeat) {
      await _controller.repeat();
    } else if (action == _NoisyAction.save) {
      await _controller.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        widget.feature.session,
        widget.feature.repository.preferences.values,
      ]),
      builder: (context, _) => GainerScaffold(
        title: 'HRV-Messung',
        children: switch (_controller.phase) {
          HrvPhase.idle => _idle(context),
          HrvPhase.settling || HrvPhase.measuring => _running(context),
          HrvPhase.result => _result(context),
        },
      ),
    );
  }

  List<Widget> _idle(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final controller = _controller;
    final reason = controller.blockedReason;
    final session = widget.feature.session;
    final median = controller.medianRestingHeartRate;
    final prefs = widget.feature.repository.preferences.values.value;
    return [
      Text(
        'Setz oder leg dich ruhig hin und atme normal. Die ersten 30 s zum '
        'Einschwingen zählen nicht.',
        style: GainerTypography.body.copyWith(color: colors.secondaryText),
      ),
      const SizedBox(height: GainerSpacing.l),
      if (!session.isBusy)
        CardioSensorSection(
          session: session,
          footerWithoutSensor: 'Für die Messung brauchst du einen Pulsgurt.',
        ),
      if (!session.isBusy) const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: 'Messdauer',
        children: [
          Padding(
            padding: const EdgeInsets.all(GainerSpacing.s),
            child: GainerSegmentedControl<int>(
              options: {
                for (
                  var minutes = CardioPreferenceValues.minHrvMinutes;
                  minutes <= CardioPreferenceValues.maxHrvMinutes;
                  minutes++
                )
                  minutes: '$minutes min',
              },
              value: controller.duration.inMinutes,
              onChanged: controller.setMinutes,
            ),
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      if (reason != null) ...[
        Text(
          reason,
          key: const ValueKey('hrv-blocked'),
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: GainerSpacing.s),
      ],
      if (controller.error case final error?) ...[
        Text(
          error,
          style: GainerTypography.label.copyWith(color: colors.destructive),
        ),
        const SizedBox(height: GainerSpacing.s),
      ],
      GainerPillButton(
        key: const ValueKey('hrv-start'),
        label: 'Messung starten',
        expand: true,
        isLoading: controller.isBusy,
        onPressed: controller.canStart ? controller.start : null,
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: 'Ruhepuls für die Zonen',
        footer: median == null
            ? 'Nach der ersten gespeicherten Messung kannst du den Median '
                  'als Ruhepuls übernehmen.'
            : controller.canAdopt
            ? 'Median der letzten ${controller.medianSampleCount} Messungen. Die Zonen '
                  'rechnen dann nach Karvonen.'
            : 'Ein Ruhepuls von $median bpm liegt außerhalb von 30 bis 120 bpm '
                  'und kann nicht für die Zonen übernommen werden.',
        children: [
          GainerListRow(
            title: 'Median Ruhepuls',
            value: median == null ? '–' : formatBpm(median),
          ),
          GainerListRow(
            title: 'Aktuell in den Zonen',
            value: prefs.restingHeartRate == null
                ? '–'
                : formatBpm(prefs.restingHeartRate!),
          ),
          Padding(
            padding: const EdgeInsets.all(GainerSpacing.s),
            child: GainerPillButton(
              key: const ValueKey('hrv-adopt'),
              label: 'Als Ruhepuls übernehmen',
              expand: true,
              variant: GainerPillVariant.tonal,
              onPressed: controller.canAdopt ? _adopt : null,
            ),
          ),
          if (_adoptMessage case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.m,
                0,
                GainerSpacing.m,
                GainerSpacing.s,
              ),
              child: Text(
                message,
                key: const ValueKey('hrv-adopt-message'),
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  Future<void> _adopt() async {
    final median = _controller.medianRestingHeartRate;
    final ok = await _controller.adoptRestingHeartRate();
    if (!mounted) return;
    setState(
      () => _adoptMessage = ok
          ? 'Ruhepuls ${formatBpm(median!)} für die Zonen übernommen.'
          : 'Der Ruhepuls konnte nicht übernommen werden.',
    );
  }

  List<Widget> _running(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final controller = _controller;
    final settling = controller.phase == HrvPhase.settling;
    final bpm = controller.liveBpm;
    return [
      GainerCard(
        padding: const EdgeInsets.symmetric(
          vertical: GainerSpacing.l,
          horizontal: GainerSpacing.m,
        ),
        child: Column(
          children: [
            Text(
              settling ? 'Einschwingen' : 'Messung läuft',
              key: const ValueKey('hrv-phase'),
              style: GainerTypography.cardTitle.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatCountdown(controller.remaining),
                key: const ValueKey('hrv-countdown'),
                style: GainerTypography.timer.copyWith(
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: GainerSpacing.s),
            Text(
              bpm == null ? 'Kein Signal' : formatBpm(bpm),
              key: const ValueKey('hrv-bpm'),
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.xs),
            Text(
              settling
                  ? 'Diese Zeit zählt nicht. Atme ruhig weiter.'
                  : 'Gültige RR-Werte: ${controller.validRrCount}',
              key: const ValueKey('hrv-rr'),
              textAlign: TextAlign.center,
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerPillButton(
        key: const ValueKey('hrv-cancel'),
        label: 'Abbrechen',
        expand: true,
        variant: GainerPillVariant.tonal,
        onPressed: controller.cancel,
      ),
    ];
  }

  List<Widget> _result(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final controller = _controller;
    final result = controller.result!;
    final saved = controller.saved;
    final storable = result.isStorable;
    return [
      GainerGroupedSection(
        header: 'Ergebnis',
        footer: storable
            ? null
            : 'Aus dieser Messung lässt sich kein Wert ableiten: Es gab zu '
                  'wenige gültige Herzschläge oder der Puls lag außerhalb von '
                  '25 bis 150 bpm. Wiederhole die Messung in Ruhe.',
        children: [
          GainerListRow(
            title: 'Ruhepuls',
            value: result.restingHeartRateBpm == null
                ? '–'
                : formatBpm(result.restingHeartRateBpm!),
          ),
          GainerListRow(
            title: 'HRV (RMSSD)',
            value: result.rmssdMs == null ? '–' : '${result.rmssdMs} ms',
          ),
          GainerListRow(
            title: 'Verworfene Schläge',
            value: formatPercent(result.artifactRatio),
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      if (saved != null) ...[
        Text(
          saved == RestingMeasurementStatus.savedToCheckIn
              ? 'Im heutigen Check-in gespeichert.'
              : 'Gespeichert. Der Wert wartet auf deinen Check-in von heute '
                    'und wird beim nächsten Speichern des Check-ins '
                    'übernommen.',
          key: const ValueKey('hrv-saved'),
          style: GainerTypography.body.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerPillButton(
          key: const ValueKey('hrv-done'),
          label: 'Fertig',
          expand: true,
          onPressed: controller.discardResult,
        ),
      ] else ...[
        if (controller.error case final error?) ...[
          Text(
            error,
            style: GainerTypography.label.copyWith(color: colors.destructive),
          ),
          const SizedBox(height: GainerSpacing.s),
        ],
        if (storable)
          GainerPillButton(
            key: const ValueKey('hrv-save'),
            label: 'Speichern',
            expand: true,
            isLoading: controller.isBusy,
            onPressed: controller.save,
          ),
        if (storable) const SizedBox(height: GainerSpacing.s),
        GainerPillButton(
          key: const ValueKey('hrv-repeat'),
          label: 'Wiederholen',
          expand: true,
          variant: storable
              ? GainerPillVariant.tonal
              : GainerPillVariant.filled,
          onPressed: controller.repeat,
        ),
      ],
    ];
  }
}

enum _NoisyAction { repeat, save }
