import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/api/coach_memory_api_models.dart';
import '../../../data/repositories/coach/coach_memory_repository.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'coach_memory_view_model.dart';

/// „Gedächtnis“: alles, was sich der Coach über den Nutzer merkt.
class CoachMemoryScreen extends StatefulWidget {
  const CoachMemoryScreen({
    required this.repository,
    this.online = true,
    super.key,
  });

  final CoachMemoryRepository repository;

  /// Das Konto wurde mit Verbindung geöffnet.
  final bool online;

  @override
  State<CoachMemoryScreen> createState() => _CoachMemoryScreenState();
}

class _CoachMemoryScreenState extends State<CoachMemoryScreen> {
  late final CoachMemoryViewModel _model;

  @override
  void initState() {
    super.initState();
    _model = CoachMemoryViewModel(widget.repository, online: widget.online)
      ..start();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _edit([ApiCoachMemory? memory]) async {
    var sheetOpen = true;
    await showCoachMemoryEditor(
      context,
      memory: memory,
      onSave: (draft) async {
        final failure = await _model.save(
          id: draft.id,
          category: draft.category,
          text: draft.text,
        );
        // Wurde das Sheet während des Speicherns geschlossen, meldet der
        // Screen den Fehler, damit er nicht verloren geht.
        if (failure != null && !sheetOpen) {
          _model.reportActionError(failure.message);
        }
        return failure;
      },
    );
    sheetOpen = false;
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

/// Eingabe des Notiz-Sheets.
class CoachMemoryDraft {
  const CoachMemoryDraft(this.category, this.text, {this.id});

  final CoachMemoryCategory category;
  final String text;

  /// Die zu ändernde Notiz; null legt eine neue an.
  final String? id;
}

/// Speichert einen Entwurf; null bei Erfolg, sonst der Grund.
typedef CoachMemorySave = Future<CoachMemorySaveFailure?> Function(
  CoachMemoryDraft draft,
);

/// Sheet zum Anlegen ([memory] null) oder Bearbeiten einer Notiz. Es ruft
/// [onSave] selbst auf und schließt erst nach Erfolg; bei einem Fehler bleibt
/// der getippte Text stehen und der Grund erscheint im Sheet. Wurde die
/// bearbeitete Notiz inzwischen gelöscht, legt erneutes Sichern sie neu an.
Future<void> showCoachMemoryEditor(
  BuildContext context, {
  ApiCoachMemory? memory,
  required CoachMemorySave onSave,
}) => showGainerSheet<void>(
  context: context,
  heightFactor: 0.65,
  builder: (_) => CoachMemoryEditor(memory: memory, onSave: onSave),
);

/// Inhalt des Notiz-Sheets; öffentlich für Tests.
class CoachMemoryEditor extends StatefulWidget {
  const CoachMemoryEditor({required this.onSave, this.memory, super.key});

  final ApiCoachMemory? memory;
  final CoachMemorySave onSave;

  @override
  State<CoachMemoryEditor> createState() => _CoachMemoryEditorState();
}

class _CoachMemoryEditorState extends State<CoachMemoryEditor> {
  late final _text = TextEditingController(text: widget.memory?.text ?? '');
  late CoachMemoryCategory _category =
      widget.memory?.category ?? CoachMemoryCategory.goal;

  /// Die bearbeitete Notiz; null legt eine neue an, auch wenn die bearbeitete
  /// inzwischen gelöscht wurde.
  late String? _id = widget.memory?.id;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && isValidCoachMemoryText(_text.text);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await widget.onSave(
      CoachMemoryDraft(_category, _text.text.trim(), id: _id),
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = failure.message;
      if (failure.entryGone) _id = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: _id == null ? 'Neue Notiz' : 'Notiz bearbeiten',
          trailing: GainerPillButton(
            key: const ValueKey('coach-memory-save'),
            label: 'Sichern',
            isLoading: _saving,
            onPressed: _canSave ? _save : null,
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
              if (_error case final message?)
                Padding(
                  padding: const EdgeInsets.only(bottom: GainerSpacing.m),
                  child: Text(
                    message,
                    key: const ValueKey('coach-memory-editor-error'),
                    style: GainerTypography.body.copyWith(
                      color: colors.destructive,
                    ),
                  ),
                ),
              GainerGroupedSection(
                footer:
                    '${coachMemoryTextLength(_text.text)} von '
                    '$coachMemoryMaxTextLength Zeichen',
                children: [
                  GainerTextFieldRow(
                    label: 'Notiz',
                    placeholder: 'z. B. Halbmarathon im Mai',
                    controller: _text,
                    fieldKey: const ValueKey('coach-memory-text'),
                    maxLines: 4,
                    inputFormatters: const [CoachMemoryLengthFormatter()],
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

/// Begrenzt die Notiz in UTF-16-Einheiten wie der Server, nicht in
/// Graphemen wie [LengthLimitingTextInputFormatter]. Gekürzt wird nur an
/// Zeichengrenzen, ein Emoji wird also nie halbiert. Wie dort mit
/// [MaxLengthEnforcement.truncateAfterCompositionEnds]: Während einer
/// IME-Komposition (etwa Japanisch oder Diktat) wird nicht gekürzt, erst
/// danach.
class CoachMemoryLengthFormatter extends TextInputFormatter {
  const CoachMemoryLengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    const max = coachMemoryMaxTextLength;
    if (newValue.text.length <= max) return newValue;
    // Schon voll: Eingabe ablehnen, statt das Ende abzuschneiden.
    if (oldValue.text.length == max && !oldValue.composing.isValid) {
      return oldValue;
    }
    if (newValue.composing.isValid) return newValue;
    final kept = StringBuffer();
    for (final character in newValue.text.characters) {
      if (kept.length + character.length > max) break;
      kept.write(character);
    }
    final text = kept.toString();
    int clamp(int offset) => offset.clamp(0, text.length);
    final composing = newValue.composing;
    return TextEditingValue(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: clamp(newValue.selection.baseOffset),
        extentOffset: clamp(newValue.selection.extentOffset),
      ),
      composing: !composing.isCollapsed && text.length > composing.start
          ? TextRange(
              start: composing.start,
              end: composing.end.clamp(0, text.length),
            )
          : TextRange.empty,
    );
  }
}
