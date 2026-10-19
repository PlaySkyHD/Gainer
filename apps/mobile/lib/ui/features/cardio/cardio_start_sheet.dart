import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_preferences.dart';
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'cardio_feature.dart';
import 'cardio_format.dart';
import 'cardio_live_screen.dart';
import 'cardio_sensor_section.dart';
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

  /// Gewählte Vorlage; null = freie Einheit mit festem Zielbereich.
  CardioTemplate? _template;
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
    _template = values.lastTemplate;
    _session.watch();
    widget.feature.repository.preferences.read().then((loaded) {
      if (!mounted || _touched) return;
      setState(() {
        _warmupSeconds = loaded.warmupSeconds;
        _zone = loaded.lastZone;
        _template = loaded.lastTemplate;
      });
      _zoneKey.currentState?.setZone(loaded.lastZone);
    });
  }

  @override
  void dispose() {
    _session.stopWatching();
    super.dispose();
  }

  CardioPreferenceValues get _values =>
      widget.feature.repository.preferences.values.value;

  /// Die Vorlage braucht Zonen, aber es ist kein Maximalpuls bekannt.
  bool get _missingZones =>
      _template != null && _template!.needsZones && _values.zones.isEmpty;

  bool get _canStart => _template != null ? !_missingZones : _zone != null;

  Future<void> _pickTemplate() async {
    final templates = _values.allTemplates;
    final picked = await showGainerActionSheet<String>(
      context: context,
      title: 'Vorlage',
      groups: [
        [
          GainerSheetAction(
            label: 'Freie Einheit',
            hint: 'Fester Zielbereich',
            icon: _template == null
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
            value: '',
          ),
          for (final template in templates)
            GainerSheetAction(
              label: template.name,
              hint:
                  '${template.phases.length} '
                  '${template.phases.length == 1 ? 'Phase' : 'Phasen'} · '
                  '${formatTemplateTotal(template.totalSeconds)}',
              icon: _template?.id == template.id
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              value: template.id,
            ),
        ],
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _touched = true;
      _error = null;
      _template = _values.templateById(picked);
      // Das Zielfeld wird neu aufgebaut; es behält den zuletzt gültigen Wert.
      if (_zone != null) _initialZone = _zone!;
    });
  }

  Future<void> _start() async {
    final zone = _zone;
    final template = _template;
    if (!_canStart || _starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _session.start(
        template: template,
        zone: template == null ? zone : null,
        warmupSeconds: _warmupSeconds,
        sensor: _selected,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on CardioTemplateResolutionException catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = error.message;
        });
      }
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
      feature: widget.feature,
    );
  }

  Widget _phaseList(CardioTemplate template) {
    final zones = _values.zones;
    final colors = GainerDesign.colorsOf(context);
    return GainerGroupedSection(
      header: 'Phasen',
      footer: _missingZones
          ? null
          : '${template.phases.length} '
                '${template.phases.length == 1 ? 'Phase' : 'Phasen'} · '
                '${formatTemplateTotal(template.totalSeconds)}. Das Ziel '
                'wechselt automatisch.',
      children: [
        for (final phase in template.phases)
          GainerListRow(title: formatTemplatePhase(phase, zones)),
        if (_missingZones)
          GainerListRow(
            key: const ValueKey('cardio-start-missing-zones'),
            title: 'Zonen fehlen',
            subtitle:
                'Diese Vorlage nutzt Pulszonen. Gib Maximalpuls oder Alter '
                'in den Cardio-Einstellungen an, dann lässt sie sich starten.',
            leadingIcon: CupertinoIcons.exclamationmark_circle,
            leadingIconBackground: colors.accent,
            showChevron: true,
            onTap: _openSettings,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final colors = GainerDesign.colorsOf(context);
    final template = _template;
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
                    CardioSensorSection(
                      session: _session,
                      onConnected: (sensor) => _selected = sensor,
                    ),
                    const SizedBox(height: GainerSpacing.l),
                    GainerGroupedSection(
                      children: [
                        GainerListRow(
                          key: const ValueKey('cardio-start-template'),
                          title: 'Vorlage',
                          // Name im Untertitel: bei großer Schrift bricht ein
                          // langer Wert sonst Zeichen für Zeichen um.
                          subtitle: template?.name ?? 'Freie Einheit',
                          showChevron: true,
                          onTap: _pickTemplate,
                        ),
                      ],
                    ),
                    const SizedBox(height: GainerSpacing.l),
                    if (template != null)
                      _phaseList(template)
                    else
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
                      onPressed: _canStart ? _start : null,
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
}
