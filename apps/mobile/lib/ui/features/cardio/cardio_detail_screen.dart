import 'package:flutter/cupertino.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/health/cardio_health_exporter.dart';
import '../../../domain/models/cardio/cardio_analysis.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../training/training_format.dart';
import '../training/workout_text_sheet.dart';
import 'cardio_feature.dart';
import 'cardio_format.dart';
import 'cardio_heart_rate_chart.dart';

/// Öffnet die Detailansicht einer gespeicherten Einheit. Liefert true, wenn
/// die Einheit dort gelöscht wurde.
Future<bool?> openCardioDetail(
  BuildContext context,
  CardioFeature feature,
  String sessionId,
) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    CupertinoPageRoute<bool>(
      builder: (_) =>
          CardioDetailScreen(feature: feature, sessionId: sessionId),
    ),
  );
}

class CardioDetailScreen extends StatefulWidget {
  const CardioDetailScreen({
    required this.feature,
    required this.sessionId,
    super.key,
  });

  final CardioFeature feature;
  final String sessionId;

  @override
  State<CardioDetailScreen> createState() => _CardioDetailScreenState();
}

class _CardioDetailScreenState extends State<CardioDetailScreen> {
  CardioSession? _session;
  CardioAnalysis? _analysis;
  CardioExportState _export = CardioExportState.none;
  bool _loaded = false;
  bool _exporting = false;
  String? _exportError;
  String? _error;

  CardioRepository get _repository => widget.feature.repository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await _repository.readSession(widget.sessionId);
      final export = await widget.feature.health.exportState(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _session = session;
        _analysis = session == null ? null : CardioAnalysis.of(session);
        _export = export;
        _loaded = true;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = 'Die Einheit konnte nicht geladen werden.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final session = _session;
    if (session == null) return;
    final local = session.startedAtUtc.toLocal();
    final confirmed = await confirmGainerDelete(
      context,
      title: 'Einheit löschen?',
      message:
          '„${session.activityType.label}“ vom ${formatShortDate(local)} '
          'verschwindet sofort aus dem Tagebuch und wird beim nächsten Sync '
          'entfernt.',
    );
    if (!confirmed || !mounted) return;
    try {
      await _repository.deleteSession(session.sessionId);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Die Einheit konnte nicht gelöscht werden.');
      }
    }
  }

  Future<void> _save({
    double? Function(CardioSession)? distanceKm,
    double? Function(CardioSession)? power,
    double? Function(CardioSession)? energy,
    String? Function(CardioSession)? notes,
  }) async {
    final current = _session;
    if (current == null) return;
    try {
      final updated = await _repository.updateDetails(
        current.sessionId,
        distanceKm: distanceKm == null
            ? current.distanceKm
            : distanceKm(current),
        averagePowerWatts: power == null
            ? current.averagePowerWatts
            : power(current),
        energyKcal: energy == null ? current.energyKcal : energy(current),
        notes: notes == null ? current.notes : notes(current),
      );
      if (mounted) {
        setState(() {
          _session = updated;
          _error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Die Änderung konnte nicht gespeichert werden.',
        );
      }
    }
  }

  Future<void> _editErgometer() async {
    final current = _session;
    if (current == null) return;
    final result = await showGainerSheet<_Ergometer>(
      context: context,
      builder: (_) => _ErgometerSheet(session: current),
    );
    if (result == null) return;
    await _save(
      distanceKm: (_) => result.distanceKm,
      power: (_) => result.powerWatts,
      energy: (_) => result.energyKcal,
    );
  }

  Future<void> _editNotes() async {
    final current = _session;
    if (current == null) return;
    final text = await showWorkoutTextSheet(
      context: context,
      title: 'Notiz',
      initialText: current.notes ?? '',
      placeholder: 'Wie war die Einheit?',
      multiline: true,
    );
    if (text == null) return;
    await _save(notes: (_) => text);
  }

  Future<void> _exportToHealth() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      await widget.feature.health.export(widget.sessionId);
      final state = await widget.feature.health.exportState(widget.sessionId);
      if (mounted) setState(() => _export = state);
    } on Object {
      if (mounted) {
        setState(() {
          _exportError =
              'Das Sichern hat nicht geklappt. Prüfe in der Health-App unter '
              '„Datenzugriff“, ob Gainer Trainings und Puls schreiben darf.';
        });
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return GainerScaffold(
      title: 'Rad-Ergometer',
      trailing: [
        if (session != null)
          GainerToolbarButton(
            icon: CupertinoIcons.trash,
            semanticLabel: 'Einheit löschen',
            onPressed: _delete,
          ),
      ],
      children: [
        if (!_loaded)
          const Center(child: CupertinoActivityIndicator())
        else if (session == null)
          _message(_error ?? 'Die Einheit wurde nicht gefunden.')
        else
          ..._content(context, session),
      ],
    );
  }

  Widget _message(String text) => GainerCard(
    child: Text(
      text,
      style: GainerTypography.body.copyWith(
        color: GainerDesign.colorsOf(context).secondaryText,
      ),
    ),
  );

  List<Widget> _content(BuildContext context, CardioSession session) {
    final colors = GainerDesign.colorsOf(context);
    final analysis = _analysis!;
    final local = session.startedAtUtc.toLocal();
    final zone = session.targetZone;
    final hasTemplate = session.phases.isNotEmpty;
    final hasSignal = session.heartRateBpm.any((bpm) => bpm > 0);
    return [
      if (_error case final error?) ...[
        GainerCard(
          child: Text(
            error,
            style: GainerTypography.body.copyWith(color: colors.destructive),
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
      ],
      GainerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${formatWeekdayShort(local)}, ${formatShortDate(local)} · '
              '${formatClockTime(local)} Uhr'
              '${session.templateName == null ? '' : ' · ${session.templateName}'}',
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.s),
            if (hasSignal)
              CardioHeartRateChart(
                heartRateBpm: session.heartRateBpm,
                sampleIntervalSeconds: session.sampleIntervalSeconds,
                zone: zone,
                phases: session.phases,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: GainerSpacing.l),
                child: Text(
                  'Kein Puls erfasst',
                  textAlign: TextAlign.center,
                  style: GainerTypography.body.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
            if (zone != null && !hasTemplate && hasSignal) ...[
              const SizedBox(height: GainerSpacing.xs),
              Text(
                'Zielbereich $zone bpm',
                style: GainerTypography.caption.copyWith(color: colors.accent),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: GainerSpacing.l),
      _metrics(session, analysis),
      if (hasTemplate) ...[
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          key: const ValueKey('cardio-detail-phases'),
          header: 'Phasen',
          children: [
            for (final phase in session.phases)
              GainerListRow(
                title: phase.name,
                subtitle: formatPhaseZone(phase),
                value: formatPhaseDuration(phase.durationSeconds),
              ),
          ],
        ),
      ],
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: 'Ergometer',
        children: [
          GainerListRow(
            key: const ValueKey('cardio-edit-ergometer'),
            title: 'Distanz',
            value: _valueOrDash(session.distanceKm, 'km'),
            showChevron: true,
            onTap: _editErgometer,
          ),
          GainerListRow(
            title: 'Ø-Leistung',
            value: _valueOrDash(session.averagePowerWatts, 'W'),
            showChevron: true,
            onTap: _editErgometer,
          ),
          GainerListRow(
            title: 'Energie',
            value: _valueOrDash(session.energyKcal, 'kcal'),
            showChevron: true,
            onTap: _editErgometer,
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: 'Notiz',
        children: [
          GainerListRow(
            key: const ValueKey('cardio-edit-notes'),
            title: session.notes ?? 'Notiz hinzufügen',
            showChevron: true,
            onTap: _editNotes,
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      _health(),
    ];
  }

  Widget _metrics(CardioSession session, CardioAnalysis analysis) {
    final average = analysis.averageBpm;
    final max = analysis.maxBpm;
    final share = analysis.zoneShare;
    final hrv = analysis.rmssdMs;
    return GainerGroupedSection(
      header: 'Kennzahlen',
      footer: hrv == null
          ? null
          : 'HRV: Während Belastung niedriger als in Ruhe; vergleiche nur '
                'ähnliche Einheiten.',
      children: [
        GainerListRow(
          title: 'Dauer',
          value: formatCardioDuration(session.duration),
        ),
        GainerListRow(
          title: 'Ø-Puls',
          value: average == null ? '–' : formatAverageBpm(average),
        ),
        GainerListRow(
          title: 'Max-Puls',
          value: max == null ? '–' : formatBpm(max),
        ),
        if (session.targetZone != null ||
            session.phases.any((phase) => phase.zone != null))
          GainerListRow(
            title: 'Im Zielbereich',
            value: share == null
                ? '–'
                : '${formatCardioDuration(analysis.timeInZone)} '
                      '(${formatPercent(share)})',
          ),
        if (hrv != null) GainerListRow(title: 'HRV (RMSSD)', value: '$hrv ms'),
        if (session.recoveryDropBpm case final drop?)
          GainerListRow(
            title: 'Erholung',
            value: '${formatBpmChange(drop)} in 1 min',
          ),
      ],
    );
  }

  Widget _health() {
    final colors = GainerDesign.colorsOf(context);
    final failed =
        _exportError != null || (_export.failed && !_export.exported);
    return GainerGroupedSection(
      header: 'Apple Health',
      footer:
          _exportError ??
          (failed
              ? 'Das letzte Sichern hat nicht geklappt. Prüfe in der '
                    'Health-App unter „Datenzugriff“, ob Gainer Trainings und '
                    'Puls schreiben darf.'
              : null),
      children: [
        if (_export.exported)
          GainerListRow(
            title: 'In Apple Health gesichert',
            leadingIcon: CupertinoIcons.checkmark_circle_fill,
          )
        else
          GainerListRow(
            key: const ValueKey('cardio-export'),
            title: 'In Apple Health sichern',
            leadingIcon: CupertinoIcons.heart,
            trailing: _exporting
                ? CupertinoActivityIndicator(color: colors.secondaryText)
                : null,
            onTap: _exporting ? null : _exportToHealth,
          ),
      ],
    );
  }

  String _valueOrDash(double? value, String unit) =>
      value == null ? '–' : '${formatCardioNumber(value)} $unit';
}

class _Ergometer {
  const _Ergometer({this.distanceKm, this.powerWatts, this.energyKcal});

  final double? distanceKm;
  final double? powerWatts;
  final double? energyKcal;
}

/// Sheet für Distanz, Ø-Leistung und Energie. Leere Felder löschen den Wert.
class _ErgometerSheet extends StatefulWidget {
  const _ErgometerSheet({required this.session});

  final CardioSession session;

  @override
  State<_ErgometerSheet> createState() => _ErgometerSheetState();
}

class _ErgometerSheetState extends State<_ErgometerSheet> {
  late final _distance = TextEditingController(
    text: _editable(widget.session.distanceKm),
  );
  late final _power = TextEditingController(
    text: _editable(widget.session.averagePowerWatts),
  );
  late final _energy = TextEditingController(
    text: _editable(widget.session.energyKcal),
  );
  final _errors = <String, String>{};

  @override
  void dispose() {
    _distance.dispose();
    _power.dispose();
    _energy.dispose();
    super.dispose();
  }

  static String _editable(double? value) {
    if (value == null) return '';
    final text = value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return text.replaceAll('.', ',');
  }

  /// Leer ist gültig (null), ein Wert im Bereich 0 bis [max] ebenfalls.
  (bool, double?) _parse(String text, double max) {
    final trimmed = text.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return (true, null);
    final value = double.tryParse(trimmed);
    if (value == null || !value.isFinite || value < 0 || value > max) {
      return (false, null);
    }
    return (true, value);
  }

  void _submit() {
    final distance = _parse(_distance.text, maxDistanceKm);
    final power = _parse(_power.text, maxPowerWatts);
    final energy = _parse(_energy.text, maxEnergyKcal);
    setState(() {
      _errors.clear();
      if (!distance.$1) _errors['distance'] = 'Erlaubt sind 0 bis 1.000 km.';
      if (!power.$1) _errors['power'] = 'Erlaubt sind 0 bis 3.000 W.';
      if (!energy.$1) _errors['energy'] = 'Erlaubt sind 0 bis 20.000 kcal.';
    });
    if (_errors.isNotEmpty) return;
    Navigator.of(context).pop(
      _Ergometer(
        distanceKm: distance.$2,
        powerWatts: power.$2,
        energyKcal: energy.$2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GainerSheetHeader(title: 'Ergometer-Werte'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GainerGroupedSection(
                    footer: 'Trage die Werte vom Display des Ergometers ein.',
                    children: [
                      GainerTextFieldRow(
                        label: 'Distanz',
                        unit: 'km',
                        controller: _distance,
                        fieldKey: const ValueKey('cardio-field-distance'),
                        keyboardType: decimal,
                        errorText: _errors['distance'],
                      ),
                      GainerTextFieldRow(
                        label: 'Ø-Leistung',
                        unit: 'W',
                        controller: _power,
                        fieldKey: const ValueKey('cardio-field-power'),
                        keyboardType: decimal,
                        errorText: _errors['power'],
                      ),
                      GainerTextFieldRow(
                        label: 'Energie',
                        unit: 'kcal',
                        controller: _energy,
                        fieldKey: const ValueKey('cardio-field-energy'),
                        keyboardType: decimal,
                        errorText: _errors['energy'],
                      ),
                    ],
                  ),
                  const SizedBox(height: GainerSpacing.l),
                  GainerPillButton(
                    key: const ValueKey('cardio-ergometer-save'),
                    label: 'Speichern',
                    expand: true,
                    onPressed: _submit,
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
