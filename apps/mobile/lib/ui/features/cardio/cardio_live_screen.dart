import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../training/training_format.dart';
import 'cardio_detail_screen.dart';
import 'cardio_feature.dart';
import 'cardio_format.dart';
import 'cardio_session_controller.dart';
import 'cardio_settings_screen.dart';
import 'cardio_zone_fields.dart';

/// Unter dieser Dauer fragt die App, ob die Einheit verworfen werden soll.
const cardioMinimumSaveDuration = Duration(seconds: 60);

/// Öffnet die Live-Ansicht der laufenden Einheit als Vollbild.
Future<void> openCardioLive(BuildContext context, CardioFeature feature) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CardioLiveScreen(feature: feature),
    ),
  );
}

class CardioLiveScreen extends StatefulWidget {
  const CardioLiveScreen({required this.feature, super.key});

  final CardioFeature feature;

  @override
  State<CardioLiveScreen> createState() => _CardioLiveScreenState();
}

class _CardioLiveScreenState extends State<CardioLiveScreen> {
  Timer? _ticker;
  bool _finishing = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Die Dauer läuft jede Sekunde weiter, auch wenn der Gurt nichts meldet.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _editZone() async {
    final session = widget.feature.session;
    final current = session.active?.targetZone;
    final zone = await showGainerSheet<CardioTargetZone>(
      context: context,
      builder: (_) => _ZoneSheet(feature: widget.feature, current: current),
    );
    if (zone == null || !mounted) return;
    try {
      await session.updateZone(zone);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Der Zielbereich konnte nicht geändert werden.',
        );
      }
    }
  }

  Future<void> _finish() async {
    final session = widget.feature.session;
    final short = session.elapsed < cardioMinimumSaveDuration;
    final action = await showGainerStackedDialog<_FinishAction>(
      context: context,
      title: short ? 'Sehr kurze Einheit' : 'Einheit beenden?',
      message: short
          ? 'Die Einheit läuft erst seit ${session.elapsed.inSeconds} s. '
                'Verwerfen oder trotzdem speichern?'
          : 'Die Einheit wird gespeichert.',
      actions: [
        if (short) ...const [
          GainerDialogAction(label: 'Speichern', value: _FinishAction.save),
          GainerDialogAction(
            label: 'Verwerfen',
            value: _FinishAction.discard,
            destructive: true,
          ),
        ] else
          const GainerDialogAction(label: 'Beenden', value: _FinishAction.save),
        const GainerDialogAction(
          label: 'Abbrechen',
          value: _FinishAction.cancel,
        ),
      ],
    );
    if (!mounted || action == null || action == _FinishAction.cancel) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      if (action == _FinishAction.discard) {
        await session.discard();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final saved = await session.finish();
      if (!mounted) return;
      _closing = true;
      await Navigator.of(context).pushReplacement<void, void>(
        CupertinoPageRoute<void>(
          builder: (_) => CardioDetailScreen(
            feature: widget.feature,
            sessionId: saved.sessionId,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() {
          _finishing = false;
          _error = 'Die Einheit konnte nicht gespeichert werden.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.feature.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isRunning && !_finishing && !_closing) {
          // Die Einheit wurde anderswo beendet.
          _closing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }
        return GainerScaffold(
          title: 'Rad-Ergometer',
          leading: GainerToolbarButton(
            icon: CupertinoIcons.chevron_down,
            semanticLabel: 'Minimieren',
            onPressed: () => Navigator.of(context).pop(),
          ),
          children: session.isRunning ? _content(context) : const [],
        );
      },
    );
  }

  List<Widget> _content(BuildContext context) {
    final session = widget.feature.session;
    final colors = GainerDesign.colorsOf(context);
    final zone = session.active?.targetZone;
    final analysis = session.currentAnalysis;
    final average = analysis?.averageBpm;
    final max = analysis?.maxBpm;
    final problem = session.bluetoothProblem;
    return [
      _Hero(
        bpm: session.liveBpm,
        state: session.zoneState,
        hasSensor: session.sensorId != null,
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        children: [
          GainerListRow(
            key: const ValueKey('cardio-live-zone'),
            title: 'Ziel',
            value: zone == null ? 'Kein Zielbereich' : '$zone bpm',
            showChevron: true,
            onTap: _editZone,
          ),
          GainerListRow(title: 'Dauer', value: formatElapsed(session.elapsed)),
          GainerListRow(
            title: 'Ø-Puls',
            value: average == null ? '–' : formatAverageBpm(average),
          ),
          GainerListRow(
            title: 'Max-Puls',
            value: max == null ? '–' : formatBpm(max),
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        children: [
          GainerListRow(
            key: const ValueKey('cardio-live-sensor'),
            title: session.sensorName ?? 'Kein Gurt',
            subtitle: session.sensorId == null
                ? 'Es wird kein Puls erfasst.'
                : _sensorSubtitle(session),
            leadingIcon: CupertinoIcons.heart_fill,
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Text(
                bluetoothProblemText(problem),
                style: GainerTypography.label.copyWith(
                  color: colors.destructive,
                ),
              ),
            ),
        ],
      ),
      if (_error case final error?) ...[
        const SizedBox(height: GainerSpacing.s),
        Text(
          error,
          style: GainerTypography.label.copyWith(color: colors.destructive),
        ),
      ],
      const SizedBox(height: GainerSpacing.l),
      GainerPillButton(
        key: const ValueKey('cardio-finish'),
        label: 'Beenden',
        expand: true,
        isLoading: _finishing,
        variant: GainerPillVariant.destructive,
        onPressed: _finish,
      ),
    ];
  }

  String _sensorSubtitle(CardioSessionController session) {
    final state = session.connectionState;
    if (state == HeartRateConnectionState.connected &&
        session.liveBpm == null) {
      return 'Kein Signal';
    }
    return cardioSensorStatus(state, batteryPercent: session.batteryPercent);
  }
}

enum _FinishAction { save, discard, cancel }

class _Hero extends StatelessWidget {
  const _Hero({
    required this.bpm,
    required this.state,
    required this.hasSensor,
  });

  final int? bpm;
  final HeartRateZoneState state;
  final bool hasSensor;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final color = cardioZoneColor(context, colors, state);
    final label = cardioZoneLabel(state, hasSensor: hasSensor);
    return GainerCard(
      padding: const EdgeInsets.symmetric(
        vertical: GainerSpacing.l,
        horizontal: GainerSpacing.m,
      ),
      child: Semantics(
        label: bpm == null ? label : '${formatBpm(bpm!)}, $label',
        excludeSemantics: true,
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    bpm?.toString() ?? '–',
                    key: const ValueKey('cardio-live-bpm'),
                    style: GainerTypography.timer.copyWith(
                      fontSize: 96,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(width: GainerSpacing.xs),
                  Text(
                    'bpm',
                    style: GainerTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: GainerSpacing.xs),
            Text(
              label,
              key: const ValueKey('cardio-live-state'),
              textAlign: TextAlign.center,
              style: GainerTypography.cardTitle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet zum Ändern des Zielbereichs während der Einheit.
class _ZoneSheet extends StatefulWidget {
  const _ZoneSheet({required this.feature, required this.current});

  final CardioFeature feature;
  final CardioTargetZone? current;

  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet> {
  late final CardioTargetZone _initial =
      widget.current ??
      widget.feature.repository.preferences.values.value.lastZone;
  late CardioTargetZone? _zone = _initial;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final preferences = widget.feature.repository.preferences;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GainerSheetHeader(title: 'Zielbereich ändern'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardioZoneFields(
                    initial: _initial,
                    zones: preferences.values.value.zones,
                    onOpenSettings: () =>
                        openCardioSettings(context, preferences: preferences),
                    onChanged: (zone) => setState(() => _zone = zone),
                  ),
                  const SizedBox(height: GainerSpacing.l),
                  GainerPillButton(
                    key: const ValueKey('cardio-zone-save'),
                    label: 'Übernehmen',
                    expand: true,
                    onPressed: _zone == null
                        ? null
                        : () => Navigator.of(context).pop(_zone),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
