import 'package:flutter/cupertino.dart';

import '../../../data/services/platform/platform_ports.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'cardio_format.dart';
import 'cardio_session_controller.dart';

/// Gruppe „Gurt“: gemerkter Gurt, Suche, Treffer und Bluetooth-Probleme. Der
/// Aufrufer sorgt dafür, dass der Controller den Status liest
/// (`session.watch()`), und baut das Widget bei dessen Änderungen neu auf.
class CardioSensorSection extends StatefulWidget {
  const CardioSensorSection({
    required this.session,
    this.onConnected,
    this.footerWithoutSensor = 'Ohne Gurt wird kein Puls erfasst.',
    super.key,
  });

  final CardioSessionController session;

  /// Wird nach erfolgreichem Verbinden aufgerufen.
  final ValueChanged<HeartRateSensor>? onConnected;
  final String footerWithoutSensor;

  @override
  State<CardioSensorSection> createState() => _CardioSensorSectionState();
}

class _CardioSensorSectionState extends State<CardioSensorSection> {
  bool _scanned = false;
  String? _error;

  CardioSessionController get _session => widget.session;

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
        _error = null;
        widget.onConnected?.call(sensor);
      } else {
        _error = 'Der Gurt konnte nicht verbunden werden.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
      footer: name == null ? widget.footerWithoutSensor : null,
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
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Text(
                error,
                style: GainerTypography.label.copyWith(
                  color: colors.destructive,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
