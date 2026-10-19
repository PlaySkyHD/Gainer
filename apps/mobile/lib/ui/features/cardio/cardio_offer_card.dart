import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_preferences.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'cardio_feature.dart';
import 'cardio_format.dart';
import 'cardio_live_screen.dart';
import 'cardio_settings_screen.dart';
import 'cardio_start_sheet.dart';

/// „Cardio anhängen“ für die Zusammenfassung eines Krafttrainings: zeigt
/// zuletzt genutzte Vorlage bzw. Zielbereich und den Gurt. „Starten“ beginnt
/// sofort mit diesen Werten, „Anpassen“ öffnet das Start-Sheet.
///
/// Die Karte fehlt, wenn die Einstellung aus ist oder schon eine Cardio-Einheit
/// oder Erholung läuft. Nach einem Start bleibt sie für diese Zusammenfassung
/// verborgen.
class CardioOfferCard extends StatefulWidget {
  const CardioOfferCard({required this.feature, super.key});

  final CardioFeature feature;

  @override
  State<CardioOfferCard> createState() => _CardioOfferCardState();
}

class _CardioOfferCardState extends State<CardioOfferCard> {
  bool _starting = false;
  bool _started = false;
  String? _error;

  CardioPreferences get _preferences => widget.feature.repository.preferences;

  @override
  void initState() {
    super.initState();
    _preferences.read().ignore();
    // Gurtstatus für die Anzeige; ohne Bluetooth bleibt er „nicht verbunden“.
    widget.feature.session.refreshStatus().ignore();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await widget.feature.session.startWithLastValues();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = error is CardioTemplateResolutionException
              ? error.message
              : 'Die Einheit konnte nicht gestartet werden.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _starting = false;
      _started = true;
    });
    await openCardioLive(context, widget.feature);
  }

  Future<void> _adjust() async {
    final started = await showCardioStartSheet(context, widget.feature);
    if (started != true || !mounted) return;
    setState(() => _started = true);
    await openCardioLive(context, widget.feature);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.feature.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session, _preferences.values]),
      builder: (context, _) {
        final values = _preferences.values.value;
        if (_started || !values.offerAfterStrength || session.isBusy) {
          return const SizedBox.shrink();
        }
        final colors = GainerDesign.colorsOf(context);
        final template = values.lastTemplate;
        final missingZones =
            template != null && template.needsZones && values.zones.isEmpty;
        final target = template != null
            ? template.name
            : 'Zielbereich ${values.lastZone} bpm';
        final strap = session.sensorId == null
            ? 'Kein Gurt – es wird kein Puls erfasst'
            : '${session.sensorName ?? 'Pulsgurt'} · '
                  '${cardioSensorStatus(session.connectionState, batteryPercent: session.batteryPercent)}';
        return Padding(
          padding: const EdgeInsets.only(top: GainerSpacing.m),
          child: GainerCard(
            key: const ValueKey('cardio-offer-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.heart_fill,
                      size: 22,
                      color: colors.accent,
                    ),
                    const SizedBox(width: GainerSpacing.xs),
                    Expanded(
                      child: Text(
                        'Cardio anhängen',
                        style: GainerTypography.cardTitle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GainerSpacing.xs),
                Text(
                  target,
                  key: const ValueKey('cardio-offer-target'),
                  style: GainerTypography.body.copyWith(
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  strap,
                  key: const ValueKey('cardio-offer-strap'),
                  style: GainerTypography.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
                if (missingZones) ...[
                  const SizedBox(height: GainerSpacing.xs),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openCardioSettings(
                      context,
                      preferences: _preferences,
                      feature: widget.feature,
                    ),
                    child: Text(
                      'Diese Vorlage braucht Pulszonen. Gib Maximalpuls oder '
                      'Alter in den Cardio-Einstellungen an.',
                      key: const ValueKey('cardio-offer-missing-zones'),
                      style: GainerTypography.label.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: GainerSpacing.xs),
                  Text(
                    error,
                    style: GainerTypography.label.copyWith(
                      color: colors.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: GainerSpacing.s),
                GainerPillButton(
                  key: const ValueKey('cardio-offer-start'),
                  label: 'Starten',
                  expand: true,
                  isLoading: _starting,
                  onPressed: missingZones ? null : _start,
                ),
                const SizedBox(height: GainerSpacing.xs),
                GainerPillButton(
                  key: const ValueKey('cardio-offer-adjust'),
                  label: 'Anpassen',
                  expand: true,
                  variant: GainerPillVariant.tonal,
                  onPressed: _starting ? null : _adjust,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
