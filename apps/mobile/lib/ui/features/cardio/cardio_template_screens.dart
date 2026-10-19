import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/cardio/cardio_preferences.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/cardio/cardio_template.dart';
import '../../../domain/models/cardio/cardio_zones.dart';
import '../../core/components/components.dart';
import '../../core/navigation/single_instance_route.dart';
import '../../core/theme.dart';
import 'cardio_format.dart';

Future<void> openCardioTemplates(
  BuildContext context, {
  required CardioPreferences preferences,
}) {
  return pushSingleInstance<void>(
    context,
    key: 'cardio-templates',
    rootNavigator: false,
    fullscreenDialog: false,
    builder: (_) => CardioTemplatesScreen(preferences: preferences),
  );
}

String _newTemplateId() => 'tpl-${DateTime.now().microsecondsSinceEpoch}';

enum _TemplateAction { edit, duplicate, delete }

/// Liste der Vorlagen: mitgelieferte (nicht löschbar, duplizierbar) und eigene
/// (Tippen bearbeitet, Wischen oder langes Drücken löscht).
class CardioTemplatesScreen extends StatefulWidget {
  const CardioTemplatesScreen({required this.preferences, super.key});

  final CardioPreferences preferences;

  @override
  State<CardioTemplatesScreen> createState() => _CardioTemplatesScreenState();
}

class _CardioTemplatesScreenState extends State<CardioTemplatesScreen> {
  CardioPreferences get _preferences => widget.preferences;

  @override
  void initState() {
    super.initState();
    _preferences.read();
  }

  Future<void> _save(CardioTemplate template) {
    return _preferences.update((current) {
      final index = current.templates.indexWhere((e) => e.id == template.id);
      if (index < 0) {
        return current.copyWith(templates: [...current.templates, template]);
      }
      final next = [...current.templates]..[index] = template;
      return current.copyWith(templates: next);
    });
  }

  Future<void> _delete(CardioTemplate template) {
    return _preferences.update(
      (current) => current.copyWith(
        templates: [
          for (final entry in current.templates)
            if (entry.id != template.id) entry,
        ],
      ),
    );
  }

  Future<void> _create() async {
    final created = await showCardioTemplateEditor(
      context,
      zones: _preferences.values.value.zones,
    );
    if (created != null) await _save(created);
  }

  Future<void> _edit(CardioTemplate template) async {
    final edited = await showCardioTemplateEditor(
      context,
      template: template,
      zones: _preferences.values.value.zones,
    );
    if (edited != null) await _save(edited);
  }

  Future<void> _duplicate(CardioTemplate template) async {
    if (_preferences.values.value.templates.length >=
        CardioPreferenceValues.maxTemplates) {
      return;
    }
    await _save(
      template.copyWith(id: _newTemplateId(), name: '${template.name} Kopie'),
    );
  }

  Future<bool> _confirmDelete(CardioTemplate template) {
    return confirmGainerDelete(
      context,
      title: '„${template.name}“ löschen?',
      message: 'Die Vorlage wird entfernt. Gespeicherte Einheiten bleiben.',
    );
  }

  Future<void> _showActions(CardioTemplate template) async {
    final action = await showGainerActionSheet<_TemplateAction>(
      context: context,
      title: template.name,
      groups: [
        [
          if (!template.builtIn)
            const GainerSheetAction(
              label: 'Bearbeiten',
              icon: CupertinoIcons.pencil,
              value: _TemplateAction.edit,
            ),
          GainerSheetAction(
            label: 'Duplizieren',
            icon: CupertinoIcons.doc_on_doc,
            value: _TemplateAction.duplicate,
            hint: template.builtIn
                ? 'Mitgelieferte Vorlagen sind fest. Die Kopie lässt sich '
                      'ändern.'
                : null,
          ),
          if (!template.builtIn)
            const GainerSheetAction(
              label: 'Löschen',
              icon: CupertinoIcons.delete,
              value: _TemplateAction.delete,
              destructive: true,
            ),
        ],
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TemplateAction.edit:
        await _edit(template);
      case _TemplateAction.duplicate:
        await _duplicate(template);
      case _TemplateAction.delete:
        if (await _confirmDelete(template)) await _delete(template);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GainerScaffold(
      title: 'Vorlagen',
      trailing: [
        GainerToolbarButton(
          icon: CupertinoIcons.add,
          semanticLabel: 'Neue Vorlage',
          onPressed: _create,
        ),
      ],
      children: [
        ValueListenableBuilder<CardioPreferenceValues>(
          valueListenable: _preferences.values,
          builder: (context, values, _) => _content(values),
        ),
      ],
    );
  }

  Widget _row(CardioTemplate template, CardioPreferenceValues values) {
    final row = GainerListRow(
      key: ValueKey('cardio-template-${template.id}'),
      title: template.name,
      subtitle:
          '${template.phases.length} '
          '${template.phases.length == 1 ? 'Phase' : 'Phasen'} · '
          '${formatTemplateTotal(template.totalSeconds)}',
      showChevron: !template.builtIn,
      onTap: template.builtIn
          ? () => _showActions(template)
          : () => _edit(template),
    );
    final pressable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showActions(template),
      child: row,
    );
    if (template.builtIn) return pressable;
    return GainerSwipeToDelete(
      dismissKey: ValueKey('cardio-template-dismiss-${template.id}'),
      confirm: () => _confirmDelete(template),
      onDeleted: () => _delete(template),
      child: pressable,
    );
  }

  Widget _content(CardioPreferenceValues values) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerGroupedSection(
          header: 'Mitgeliefert',
          footer:
              'Halte eine Vorlage gedrückt, um sie zu duplizieren und '
              'anzupassen.',
          children: [
            for (final template in CardioTemplate.builtIns)
              _row(template, values),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        if (values.templates.isEmpty)
          const GainerGroupedSection(
            header: 'Eigene',
            children: [
              Padding(
                padding: EdgeInsets.all(GainerSpacing.m),
                child: _Caption(
                  'Noch keine eigenen Vorlagen. Tippe oben auf „+“, um eine '
                  'anzulegen.',
                ),
              ),
            ],
          )
        else
          GainerGroupedSection(
            header: 'Eigene',
            children: [
              for (final template in values.templates) _row(template, values),
            ],
          ),
      ],
    );
  }
}

/// Öffnet den Editor als Sheet; liefert die gesicherte Vorlage oder null.
Future<CardioTemplate?> showCardioTemplateEditor(
  BuildContext context, {
  CardioTemplate? template,
  List<CardioZone> zones = const [],
}) {
  return showGainerSheet<CardioTemplate>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => CardioTemplateEditor(template: template, zones: zones),
  );
}

enum _PhaseAction { moveUp, moveDown, duplicate, delete }

/// Editor einer Vorlage: Name und Phasen. „Sichern“ ist erst aktiv, wenn die
/// Vorlage dem Vertrag entspricht; der Grund steht darunter.
class CardioTemplateEditor extends StatefulWidget {
  const CardioTemplateEditor({this.template, this.zones = const [], super.key});

  final CardioTemplate? template;
  final List<CardioZone> zones;

  @override
  State<CardioTemplateEditor> createState() => _CardioTemplateEditorState();
}

class _CardioTemplateEditorState extends State<CardioTemplateEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.template?.name ?? '',
  );
  late List<CardioTemplatePhase> _phases = [
    ...?widget.template?.phases,
    if (widget.template == null)
      const CardioTemplatePhase(
        name: 'Belastung',
        durationSeconds: 300,
        target: CardioZoneTarget(2),
      ),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  CardioTemplate get _draft => CardioTemplate(
    id: widget.template?.id ?? _newTemplateId(),
    name: _name.text.trim(),
    phases: _phases,
  );

  Future<void> _editPhase(int index) async {
    final edited = await showGainerSheet<CardioTemplatePhase>(
      context: context,
      builder: (_) =>
          CardioPhaseEditor(phase: _phases[index], zones: widget.zones),
    );
    if (edited == null || !mounted) return;
    setState(() => _phases = [..._phases]..[index] = edited);
  }

  Future<void> _addPhase() async {
    final edited = await showGainerSheet<CardioTemplatePhase>(
      context: context,
      builder: (_) => CardioPhaseEditor(
        phase: CardioTemplatePhase(
          name: _phases.isEmpty ? 'Belastung' : 'Erholung',
          durationSeconds: 300,
          target: const CardioZoneTarget(2),
        ),
        zones: widget.zones,
        isNew: true,
      ),
    );
    if (edited == null || !mounted) return;
    setState(() => _phases = [..._phases, edited]);
  }

  Future<void> _phaseActions(int index) async {
    final action = await showGainerActionSheet<_PhaseAction>(
      context: context,
      title: _phases[index].name,
      groups: [
        [
          if (index > 0)
            const GainerSheetAction(
              label: 'Nach oben',
              icon: CupertinoIcons.arrow_up,
              value: _PhaseAction.moveUp,
            ),
          if (index < _phases.length - 1)
            const GainerSheetAction(
              label: 'Nach unten',
              icon: CupertinoIcons.arrow_down,
              value: _PhaseAction.moveDown,
            ),
          if (_phases.length < CardioPhase.maxPhases)
            const GainerSheetAction(
              label: 'Duplizieren',
              icon: CupertinoIcons.doc_on_doc,
              value: _PhaseAction.duplicate,
            ),
          const GainerSheetAction(
            label: 'Löschen',
            icon: CupertinoIcons.delete,
            value: _PhaseAction.delete,
            destructive: true,
          ),
        ],
      ],
    );
    if (action == null || !mounted) return;
    setState(() {
      final next = [..._phases];
      switch (action) {
        case _PhaseAction.moveUp:
          next.insert(index - 1, next.removeAt(index));
        case _PhaseAction.moveDown:
          next.insert(index + 1, next.removeAt(index));
        case _PhaseAction.duplicate:
          next.insert(index + 1, next[index]);
        case _PhaseAction.delete:
          next.removeAt(index);
      }
      _phases = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final draft = _draft;
    final error = draft.validate();
    final summary =
        '${_phases.length} ${_phases.length == 1 ? 'Phase' : 'Phasen'} · '
        '${formatTemplateTotal(draft.totalSeconds)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: widget.template == null ? 'Neue Vorlage' : 'Vorlage',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(GainerSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GainerGroupedSection(
                  children: [
                    GainerTextFieldRow(
                      label: 'Name',
                      controller: _name,
                      fieldKey: const ValueKey('cardio-template-name'),
                      placeholder: 'z. B. Intervalle',
                      textAlign: TextAlign.right,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          CardioTemplate.maxNameLength,
                        ),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
                const SizedBox(height: GainerSpacing.l),
                GainerGroupedSection(
                  header: 'Phasen',
                  footer:
                      '$summary. Tippe auf eine Phase zum Ändern, halte sie '
                      'gedrückt zum Verschieben, Duplizieren oder Löschen.',
                  children: [
                    for (var i = 0; i < _phases.length; i++)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () => _phaseActions(i),
                        child: GainerListRow(
                          key: ValueKey('cardio-template-phase-$i'),
                          title: _phases[i].name,
                          // Dauer im Untertitel, damit der Name bei großer
                          // Schrift die ganze Zeilenbreite nutzt.
                          subtitle:
                              '${formatPhaseDuration(_phases[i].durationSeconds)}'
                              ' · ${formatTemplateTarget(_phases[i].target, widget.zones)}',
                          showChevron: true,
                          onTap: () => _editPhase(i),
                        ),
                      ),
                    GainerListRow(
                      key: const ValueKey('cardio-template-add-phase'),
                      title: 'Phase hinzufügen',
                      leadingIcon: CupertinoIcons.add_circled_solid,
                      onTap: _phases.length >= CardioPhase.maxPhases
                          ? null
                          : _addPhase,
                    ),
                  ],
                ),
                if (_phases.length >= CardioPhase.maxPhases)
                  const Padding(
                    padding: EdgeInsets.only(top: GainerSpacing.xs),
                    child: _Caption(
                      'Mehr als 30 Phasen sind nicht möglich. Lösche eine '
                      'Phase, um eine neue anzulegen.',
                    ),
                  ),
                if (error != null) ...[
                  const SizedBox(height: GainerSpacing.s),
                  Text(
                    error,
                    key: const ValueKey('cardio-template-error'),
                    style: GainerTypography.label.copyWith(
                      color: colors.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: GainerSpacing.l),
                GainerPillButton(
                  key: const ValueKey('cardio-template-save'),
                  label: 'Sichern',
                  expand: true,
                  onPressed: error == null
                      ? () => Navigator.of(context).pop(draft)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _TargetType { zone, bpm, none }

/// Eine Phase: Name, Dauer (Minuten:Sekunden) und Ziel.
class CardioPhaseEditor extends StatefulWidget {
  const CardioPhaseEditor({
    required this.phase,
    this.zones = const [],
    this.isNew = false,
    super.key,
  });

  final CardioTemplatePhase phase;
  final List<CardioZone> zones;
  final bool isNew;

  @override
  State<CardioPhaseEditor> createState() => _CardioPhaseEditorState();
}

class _CardioPhaseEditorState extends State<CardioPhaseEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.phase.name,
  );
  late final TextEditingController _low = TextEditingController(
    text: switch (widget.phase.target) {
      CardioBpmTarget(:final low) => '$low',
      _ => '120',
    },
  );
  late final TextEditingController _high = TextEditingController(
    text: switch (widget.phase.target) {
      CardioBpmTarget(:final high) => '$high',
      _ => '140',
    },
  );
  late int _seconds = widget.phase.durationSeconds;
  late _TargetType _type = switch (widget.phase.target) {
    CardioZoneTarget() => _TargetType.zone,
    CardioBpmTarget() => _TargetType.bpm,
    CardioNoTarget() => _TargetType.none,
  };
  late int _zoneNumber = switch (widget.phase.target) {
    CardioZoneTarget(:final number) => number,
    _ => 2,
  };

  @override
  void dispose() {
    _name.dispose();
    _low.dispose();
    _high.dispose();
    super.dispose();
  }

  CardioPhaseTarget? get _target => switch (_type) {
    _TargetType.zone => CardioZoneTarget(_zoneNumber),
    _TargetType.none => const CardioNoTarget(),
    _TargetType.bpm => () {
      final low = int.tryParse(_low.text.trim());
      final high = int.tryParse(_high.text.trim());
      if (low == null || high == null) return null;
      final target = CardioBpmTarget(low, high);
      return CardioTargetZone(lowBpm: low, highBpm: high).isValid
          ? target
          : null;
    }(),
  };

  String? get _error {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Die Phase braucht einen Namen.';
    if (_seconds < CardioPhase.minDurationSeconds ||
        _seconds > CardioPhase.maxDurationSeconds) {
      return 'Die Dauer muss zwischen 0:30 und 60:00 liegen.';
    }
    if (_target == null) return zoneRangeMessage;
    return null;
  }

  static const zoneRangeMessage =
      'Der Pulsbereich liegt zwischen 40 und 230 bpm, „von“ muss kleiner als '
      '„bis“ sein.';

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final error = _error;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ];
    final zone = widget.zones
        .where((entry) => entry.number == _zoneNumber)
        .firstOrNull;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GainerSheetHeader(title: widget.isNew ? 'Neue Phase' : 'Phase'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GainerGroupedSection(
                    children: [
                      GainerTextFieldRow(
                        label: 'Name',
                        controller: _name,
                        fieldKey: const ValueKey('cardio-phase-name'),
                        placeholder: 'z. B. Belastung',
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            CardioPhase.maxNameLength,
                          ),
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: GainerSpacing.l),
                  GainerGroupedSection(
                    header: 'Dauer in Minuten und Sekunden',
                    children: [
                      SizedBox(
                        height: 150,
                        child: CupertinoTimerPicker(
                          key: const ValueKey('cardio-phase-duration'),
                          mode: CupertinoTimerPickerMode.ms,
                          initialTimerDuration: Duration(
                            seconds: _seconds.clamp(0, 3599),
                          ),
                          onTimerDurationChanged: (value) =>
                              setState(() => _seconds = value.inSeconds),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GainerSpacing.l),
                  GainerGroupedSection(
                    header: 'Ziel',
                    footer: switch (_type) {
                      _TargetType.zone when zone != null =>
                        'Zone $_zoneNumber: ${zone.lowBpm}–${zone.highBpm} bpm',
                      _TargetType.zone =>
                        'Für Zonen braucht Gainer deinen Maximalpuls in den '
                            'Cardio-Einstellungen. Ohne ihn lässt sich die '
                            'Vorlage nicht starten.',
                      _ => null,
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(GainerSpacing.s),
                        child: GainerSegmentedControl<_TargetType>(
                          options: const {
                            _TargetType.zone: 'Zone',
                            _TargetType.bpm: 'bpm',
                            _TargetType.none: 'Kein Ziel',
                          },
                          value: _type,
                          onChanged: (value) => setState(() => _type = value),
                        ),
                      ),
                      if (_type == _TargetType.zone)
                        Padding(
                          padding: const EdgeInsets.all(GainerSpacing.s),
                          child: GainerSegmentedControl<int>(
                            options: const {
                              1: 'Z1',
                              2: 'Z2',
                              3: 'Z3',
                              4: 'Z4',
                              5: 'Z5',
                            },
                            value: _zoneNumber,
                            onChanged: (value) =>
                                setState(() => _zoneNumber = value),
                          ),
                        ),
                      if (_type == _TargetType.bpm) ...[
                        GainerTextFieldRow(
                          label: 'Von',
                          unit: 'bpm',
                          controller: _low,
                          fieldKey: const ValueKey('cardio-phase-low'),
                          keyboardType: TextInputType.number,
                          inputFormatters: digits,
                          onChanged: (_) => setState(() {}),
                        ),
                        GainerTextFieldRow(
                          label: 'Bis',
                          unit: 'bpm',
                          controller: _high,
                          fieldKey: const ValueKey('cardio-phase-high'),
                          keyboardType: TextInputType.number,
                          inputFormatters: digits,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: GainerSpacing.s),
                    Text(
                      error,
                      key: const ValueKey('cardio-phase-error'),
                      style: GainerTypography.label.copyWith(
                        color: colors.destructive,
                      ),
                    ),
                  ],
                  const SizedBox(height: GainerSpacing.l),
                  GainerPillButton(
                    key: const ValueKey('cardio-phase-save'),
                    label: 'Übernehmen',
                    expand: true,
                    onPressed: error != null
                        ? null
                        : () => Navigator.of(context).pop(
                            CardioTemplatePhase(
                              name: _name.text.trim(),
                              durationSeconds: _seconds,
                              target: _target!,
                            ),
                          ),
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
