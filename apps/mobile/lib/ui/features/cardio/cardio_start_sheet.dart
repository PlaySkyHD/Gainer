import 'package:flutter/cupertino.dart';

import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'cardio_feature.dart';
import 'cardio_format.dart';
import 'cardio_live_screen.dart';
import 'cardio_session_controller.dart';
import 'cardio_settings_screen.dart';
import 'cardio_warmup_picker.dart';
import 'cardio_zone_fields.dart';

/// Startet Cardio: läuft schon eine Einheit, öffnet sich die Live-Ansicht,
/// sonst das Start-Sheet und nach „Starten“ die Live-Ansicht.
Future<void> startOrOpenCardio(
  BuildContext context,
  CardioFeature feature,
) async {
  if (feature.session.isRunning) {
    await openCardioLive(context, feature);
    return;
  }
  final started = await showCardioStartSheet(context, feature);
  if (started == true && context.mounted) {
    await openCardioLive(context, feature);
  }
}

/// Zeigt das Start-Sheet; liefert true, wenn die Einheit gestartet wurde.
Future<bool?> showCardioStartSheet(
  BuildContext context,
  CardioFeature feature,
) {
  return showGainerSheet<bool>(
    context: context,
    builder: (_) => CardioStartSheet(feature: feature),
  );
}

class CardioStartSheet extends StatefulWidget {
  const CardioStartSheet({required this.feature, super.key});

  final CardioFeature feature;

  @override
  State<CardioStartSheet> createState() => _CardioStartSheetState();
}

class _CardioStartSheetState extends State<CardioStartSheet> {
  final _zoneKey = GlobalKey<CardioZoneFieldsState>();
  CardioTargetZone? _zone;
  CardioTargetZone _initialZone = const CardioTargetZone(
    lowBpm: 120,
    highBpm: 140,
  );
  int _warmupSeconds = 180;
  bool _touched = false;
  bool _scanned = false;
  bool _starting = false;
  HeartRateSensor? _selected;
  String? _error;

  CardioSessionController get _session => widget.feature.session;

  @override
  void initState() {
    super.initState();
    final values = widget.feature.repository.preferences.values.value;
    _initialZone = values.lastZone;
    _zone = _initialZone;
    _warmupSeconds = values.warmupSeconds;
    _session.watch();
    widget.feature.repository.preferences.read().then((loaded) {
      if (!mounted || _touched) return;
      setState(() {
        _warmupSeconds = loaded.warmupSeconds;
        _zone = loaded.lastZone;
      });
      _zoneKey.currentState?.setZone(loaded.lastZone);
    });
  }

  @override
  void dispose() {
    _session.stopWatching();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    await _session.scan();
    if (mounted) setState(() => _scanned = true);
  }

  Future<void> _connect(HeartRateSensor sensor) async {
    final ok = await _session.connect(sensor.id);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _selected = sensor;
      } else {
        _error = 'Der Gurt konnte nicht verbunden werden.';
      }
    });
  }

  Future<void> _start() async {
    final zone = _zone;
    if (zone == null || _starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _session.start(
        zone: zone,
        warmupSeconds: _warmupSeconds,
        sensor: _selected,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Die Einheit konnte nicht gestartet werden.';
        });
      }
    }
  }

  Future<void> _openSettings() async {
    await openCardioSettings(
      context,
      preferences: widget.feature.repository.preferences,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final colors = GainerDesign.colorsOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GainerSheetHeader(title: 'Cardio starten'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  _session,
                  widget.feature.repository.preferences.values,
                ]),
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sensorSection(context),
                    const SizedBox(height: GainerSpacing.l),
                    CardioZoneFields(
                      key: _zoneKey,
                      initial: _initialZone,
                      zones: widget
                          .feature
                          .repository
                          .preferences
                          .values
                          .value
                          .zones,
                      onOpenSettings: _openSettings,
                      onChanged: (zone) {
                        _touched = true;
                        setState(() => _zone = zone);
                      },
                    ),
                    const SizedBox(height: GainerSpacing.l),
                    GainerGroupedSection(
                      header: 'Aufwärmen ohne Alarm in Minuten',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(GainerSpacing.s),
                          child: CardioWarmupPicker(
                            seconds: _warmupSeconds,
                            onChanged: (seconds) => setState(() {
                              _touched = true;
                              _warmupSeconds = seconds;
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: GainerSpacing.s),
                      Text(
                        error,
                        style: GainerTypography.label.copyWith(
                          color: colors.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: GainerSpacing.l),
                    GainerPillButton(
                      key: const ValueKey('cardio-start'),
                      label: 'Starten',
                      expand: true,
                      isLoading: _starting,
                      onPressed: _zone == null ? null : _start,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorSection(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final session = _session;
    final problem = session.bluetoothProblem;
    final name = session.sensorName;
    final others = [
      for (final sensor in session.sensors)
        if (sensor.id != session.sensorId) sensor,
    ];
    return GainerGroupedSection(
      header: 'Gurt',
      footer: name == null ? 'Ohne Gurt wird kein Puls erfasst.' : null,
      children: [
        if (problem != null)
          Padding(
            padding: const EdgeInsets.all(GainerSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bluetoothProblemText(problem),
                  key: const ValueKey('cardio-bluetooth-problem'),
                  style: GainerTypography.body.copyWith(
                    color: colors.destructive,
                  ),
                ),
                if (problem != BluetoothProblem.unsupported &&
                    session.openSettings != null) ...[
                  const SizedBox(height: GainerSpacing.s),
                  GainerPillButton(
                    key: const ValueKey('cardio-open-settings'),
                    label: 'Einstellungen öffnen',
                    variant: GainerPillVariant.tonal,
                    onPressed: session.openSettings,
                  ),
                ],
              ],
            ),
          ),
        if (name != null)
          GainerListRow(
            title: name,
            subtitle: cardioSensorStatus(
              session.connectionState,
              batteryPercent: session.batteryPercent,
            ),
            leadingIcon: CupertinoIcons.heart_fill,
          ),
        if (problem == null) ...[
          GainerListRow(
            key: const ValueKey('cardio-scan'),
            title: name == null ? 'Gurt suchen' : 'Anderen Gurt suchen',
            leadingIcon: CupertinoIcons.search,
            trailing: session.isScanning
                ? const CupertinoActivityIndicator()
                : null,
            onTap: session.isScanning ? null : _scan,
          ),
          for (final sensor in others)
            GainerListRow(
              key: ValueKey('cardio-sensor-${sensor.id}'),
              title: sensor.name,
              subtitle: sensor.isConnected ? 'Verbunden' : null,
              leadingIcon: CupertinoIcons.antenna_radiowaves_left_right,
              onTap: () => _connect(sensor),
            ),
          if (_scanned && !session.isScanning && others.isEmpty)
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Text(
                'Kein Gurt gefunden. Lege den Gurt an und prüfe, ob er nicht '
                'mit einem anderen Gerät verbunden ist.',
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
