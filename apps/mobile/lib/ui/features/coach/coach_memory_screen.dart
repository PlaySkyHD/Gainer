import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/api/coach_memory_api_models.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'coach_memory_view_model.dart';

/// „Gedächtnis“: alles, was sich der Coach über den Nutzer merkt.
class CoachMemoryScreen extends StatefulWidget {
  const CoachMemoryScreen({required this.viewModel, super.key});

  final CoachMemoryViewModel viewModel;

  @override
  State<CoachMemoryScreen> createState() => _CoachMemoryScreenState();
}

class _CoachMemoryScreenState extends State<CoachMemoryScreen> {
  CoachMemoryViewModel get _model => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _model.start();
  }

  Future<void> _edit([ApiCoachMemory? memory]) async {
    final draft = await showCoachMemoryEditor(context, memory: memory);
    if (draft == null || !mounted) return;
    await _model.save(
      id: memory?.id,
      category: draft.category,
      text: draft.text,
    );
  }

  Future<bool> _confirmDelete(ApiCoachMemory memory) async {
    if (!_model.canEdit) return false;
    final confirmed = await confirmGainerDelete(
      context,
      title: 'Notiz löschen?',
      message: 'Der Coach berücksichtigt „${memory.text}“ danach nicht mehr.',
    );
    if (!confirmed) return false;
    return _model.delete(memory.id);
  }

  Future<void> _forgetAll() async {
    final confirmed = await confirmGainerDelete(
      context,
      title: 'Alles vergessen?',
      message:
          'Alle Notizen werden gelöscht. Der Coach kennt danach keine deiner '
          'Angaben mehr.',
      deleteLabel: 'Alles vergessen',
    );
    if (!confirmed || !mounted) return;
    await _model.deleteAll();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final colors = GainerDesign.colorsOf(context);
      return GainerScaffold(
        title: 'Gedächtnis',
        trailing: [
          GainerToolbarButton(
            key: const ValueKey('coach-memory-add'),
            icon: CupertinoIcons.add,
            semanticLabel: 'Notiz hinzufügen',
            onPressed: _model.canAdd ? _edit : null,
          ),
        ],
        children: [
          ..._content(colors),
          if (_model.actionError case final message?)
            Padding(
              padding: const EdgeInsets.only(top: GainerSpacing.m),
              child: Text(
                message,
                key: const ValueKey('coach-memory-error'),
                textAlign: TextAlign.center,
                style: GainerTypography.body.copyWith(
                  color: colors.destructive,
                ),
              ),
            ),
        ],
      );
    },
  );

  List<Widget> _content(GainerColors colors) {
    if (_model.isLoading && !_model.isLoaded) {
      return const [
        Padding(
          padding: EdgeInsets.all(GainerSpacing.l),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    if (!_model.isLoaded) {
      return [
        GainerGroupedSection(
          footer: _model.loadError,
          children: [
            GainerListRow(
              key: const ValueKey('coach-memory-reload'),
              title: 'Erneut laden',
              leadingIcon: CupertinoIcons.arrow_clockwise,
              onTap: _model.load,
            ),
          ],
        ),
      ];
    }
    final groups = _model.groups;
    return [
      if (groups.isEmpty)
        GainerGroupedSection(
          children: [
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Text(
                'Noch keine Notizen. Erzählst du dem Coach etwas Dauerhaftes, '
                'etwa ein Ziel oder eine Unverträglichkeit, schlägt er eine '
                'Notiz vor. Du kannst auch selbst welche hinzufügen.',
                style: GainerTypography.body.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ),
      for (final (index, (category, entries)) in groups.indexed) ...[
        if (index > 0) const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: category.pluralLabel,
          children: [for (final memory in entries) _row(memory)],
        ),
      ],
      const SizedBox(height: GainerSpacing.xs),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.m),
        child: Text(
          _footer(),
          key: const ValueKey('coach-memory-footer'),
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
      ),
      if (_model.isOffline) ...[
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          footer:
              'Keine Verbindung. Änderungen sind erst wieder online möglich.',
          children: [
            GainerListRow(
              key: const ValueKey('coach-memory-reload'),
              title: 'Erneut laden',
              leadingIcon: CupertinoIcons.arrow_clockwise,
              onTap: _model.load,
            ),
          ],
        ),
      ],
      if (_model.items.isNotEmpty) ...[
        const SizedBox(height: GainerSpacing.l),
        GainerPillButton(
          key: const ValueKey('coach-memory-forget-all'),
          label: 'Alles vergessen',
          variant: GainerPillVariant.destructive,
          expand: true,
          onPressed: _model.canEdit ? _forgetAll : null,
        ),
      ],
    ];
  }

  String _footer() {
    final count = _model.items.length;
    final usage = count == 1
        ? '1 von ${_model.maxEntries} Notizen.'
        : '$count von ${_model.maxEntries} Notizen.';
    final full = _model.isFull
        ? ' Lösche eine Notiz, um Platz zu schaffen.'
        : '';
    return '$usage$full Der Coach liest sie als Angaben über dich, nicht als '
        'Anweisungen. Notizen bleiben, bis du sie löschst.';
  }

  Widget _row(ApiCoachMemory memory) {
    final row = GainerListRow(
      key: ValueKey('coach-memory-${memory.id}'),
      title: memory.text,
      showChevron: _model.canEdit,
      onTap: _model.canEdit ? () => _edit(memory) : null,
    );
    // Nicht an isBusy koppeln: Während des Löschens muss das Wischen
    // bestehen bleiben, sonst bricht seine Animation ab.
    if (!_model.isLoaded || _model.isOffline) return row;
    return GainerSwipeToDelete(
      dismissKey: ValueKey('coach-memory-dismiss-${memory.id}'),
      confirm: () => _confirmDelete(memory),
      onDeleted: () => _model.removeLocally(memory.id),
      child: row,
    );
  }
}

/// Ergebnis des Notiz-Sheets.
class CoachMemoryDraft {
  const CoachMemoryDraft(this.category, this.text);

  final CoachMemoryCategory category;
  final String text;
}

/// Sheet zum Anlegen ([memory] null) oder Bearbeiten einer Notiz.
Future<CoachMemoryDraft?> showCoachMemoryEditor(
  BuildContext context, {
  ApiCoachMemory? memory,
}) => showGainerSheet<CoachMemoryDraft>(
  context: context,
  heightFactor: 0.65,
  builder: (_) => CoachMemoryEditor(memory: memory),
);

/// Inhalt des Notiz-Sheets; öffentlich für Tests.
class CoachMemoryEditor extends StatefulWidget {
  const CoachMemoryEditor({this.memory, super.key});

  final ApiCoachMemory? memory;

  @override
  State<CoachMemoryEditor> createState() => _CoachMemoryEditorState();
}

class _CoachMemoryEditorState extends State<CoachMemoryEditor> {
  late final _text = TextEditingController(text: widget.memory?.text ?? '');
  late CoachMemoryCategory _category =
      widget.memory?.category ?? CoachMemoryCategory.goal;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSave {
    final text = _text.text.trim();
    return text.isNotEmpty && text.length <= coachMemoryMaxTextLength;
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: widget.memory == null ? 'Neue Notiz' : 'Notiz bearbeiten',
          trailing: GainerPillButton(
            key: const ValueKey('coach-memory-save'),
            label: 'Sichern',
            onPressed: _canSave
                ? () =>
                      Navigator.of(context)
                          .pop(CoachMemoryDraft(_category, _text.text.trim()))
                : null,
          ),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              GainerSpacing.s,
              GainerSpacing.m,
              GainerSpacing.l,
            ),
            children: [
              GainerGroupedSection(
                footer:
                    '${_text.text.trim().length} von '
                    '$coachMemoryMaxTextLength Zeichen',
                children: [
                  GainerTextFieldRow(
                    label: 'Notiz',
                    placeholder: 'z. B. Halbmarathon im Mai',
                    controller: _text,
                    fieldKey: const ValueKey('coach-memory-text'),
                    maxLines: 4,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        coachMemoryMaxTextLength,
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.m),
              GainerGroupedSection(
                header: 'Art',
                children: [
                  for (final category in CoachMemoryCategory.values)
                    GainerListRow(
                      key: ValueKey('coach-memory-category-${category.name}'),
                      title: category.label,
                      trailing: _category == category
                          ? Icon(
                              CupertinoIcons.checkmark,
                              color: colors.accent,
                              size: 18,
                            )
                          : null,
                      onTap: () => setState(() => _category = category),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
