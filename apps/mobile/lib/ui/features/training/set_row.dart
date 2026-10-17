import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/theme.dart';

/// Eine Satzzeile: Satzlabel, Felder für Gewicht und Wiederholungen (optional
/// RIR und Notiz) und das Satzmenü. Gültige Eingaben werden sofort an die
/// Callbacks gemeldet; ungültige markiert das Feld und ändern nichts.
/// Zahlenfelder einer Satzzeile.
enum SetField { weight, repetitions, rir }

/// Fokusknoten aller Zahlenfelder der Seite. Die Leiste über der Tastatur
/// springt in Lesereihenfolge von Feld zu Feld, nicht über die Traversierung
/// des Widgetbaums.
class SetFieldFocus {
  final Map<String, FocusNode> _nodes = {};

  FocusNode node(String setId, SetField field) =>
      _nodes.putIfAbsent('$setId:${field.name}', FocusNode.new);

  /// Verschiebt den Fokus vom aktuell fokussierten Feld zum Nachbarn in [order].
  /// Liefert false, wenn kein Feld aus [order] den Fokus hat oder es keinen
  /// Nachbarn gibt.
  bool move(Iterable<(String, SetField)> order, {required bool forward}) {
    final focused = FocusManager.instance.primaryFocus;
    final nodes = [for (final (setId, field) in order) node(setId, field)];
    final index = nodes.indexWhere((node) => identical(node, focused));
    if (index < 0) return false;
    final target = index + (forward ? 1 : -1);
    if (target < 0 || target >= nodes.length) return false;
    nodes[target].requestFocus();
    return true;
  }

  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}

class SetRow extends StatelessWidget {
  const SetRow({
    required this.loggedSet,
    required this.label,
    required this.kind,
    required this.unit,
    required this.showRir,
    required this.weightFocus,
    required this.repetitionsFocus,
    required this.rirFocus,
    required this.onWeightChanged,
    required this.onRepetitionsChanged,
    required this.onRirChanged,
    required this.onLabelTap,
    required this.onNotesTap,
    required this.onMenuTap,
    this.previous,
    this.onEditingChanged,
    super.key,
  });

  final LoggedSet loggedSet;

  /// Satzlabel: Nummer, „W“ oder „D“.
  final String label;
  final ExerciseKind kind;
  final WeightUnit unit;
  final bool showRir;

  /// Vorwert an derselben Position; zeigt sich nur in leeren Feldern.
  final LoggedSet? previous;
  final FocusNode weightFocus;
  final FocusNode repetitionsFocus;
  final FocusNode rirFocus;
  final ValueChanged<double?> onWeightChanged;
  final ValueChanged<int?> onRepetitionsChanged;
  final ValueChanged<int?> onRirChanged;
  final VoidCallback onLabelTap;
  final VoidCallback onNotesTap;
  final VoidCallback onMenuTap;

  /// Meldet, ob gerade ein Zahlenfeld dieser Zeile den Fokus hat.
  final ValueChanged<bool>? onEditingChanged;

  @override
  Widget build(BuildContext context) {
    final set = loggedSet;
    final colors = GainerDesign.colorsOf(context);
    final weightPlaceholder = previous?.weightKg == null
        ? null
        : formatWeight(previous!.weightKg!, unit);
    final repetitionsPlaceholder = previous?.repetitions?.toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: _LabelCircle(label: label, colors: colors, onTap: onLabelTap),
        ),
        const SizedBox(width: GainerSpacing.xs),
        if (kind != ExerciseKind.bodyweightOnly) ...[
          Expanded(
            flex: 3,
            child: _NumberInput<double>(
              label: _weightLabel(kind, unit),
              text: set.weightKg == null
                  ? ''
                  : formatWeight(set.weightKg!, unit),
              placeholder: weightPlaceholder,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              focusNode: weightFocus,
              parse: (text, {required committing}) =>
                  _parseWeight(text, unit, committing: committing),
              format: (value) => value == null ? '' : formatWeight(value, unit),
              onCommit: onWeightChanged,
              onFocusChanged: _focusChanged,
            ),
          ),
          const SizedBox(width: GainerSpacing.xxs),
        ],
        Expanded(
          flex: 3,
          child: _NumberInput<int>(
            label: 'Wdh.',
            text: set.repetitions?.toString() ?? '',
            placeholder: repetitionsPlaceholder,
            keyboard: TextInputType.number,
            focusNode: repetitionsFocus,
            parse: (text, {required committing}) => _parseRepetitions(text),
            format: (value) => value?.toString() ?? '',
            onCommit: onRepetitionsChanged,
            onFocusChanged: _focusChanged,
          ),
        ),
        if (showRir) ...[
          const SizedBox(width: GainerSpacing.xxs),
          Expanded(
            flex: 2,
            child: _NumberInput<int>(
              label: 'RIR',
              text: set.rir?.toString() ?? '',
              keyboard: TextInputType.number,
              focusNode: rirFocus,
              parse: (text, {required committing}) => _parseRir(text),
              format: (value) => value?.toString() ?? '',
              onCommit: onRirChanged,
              onFocusChanged: _focusChanged,
            ),
          ),
        ],
        const SizedBox(width: GainerSpacing.xxs),
        Expanded(
          flex: 2,
          child: _NotesCell(notes: set.notes, onTap: onNotesTap),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(36),
          onPressed: onMenuTap,
          child: Semantics(
            label: 'Satzmenü',
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Icon(
                CupertinoIcons.ellipsis,
                size: 20,
                color: colors.secondaryText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _focusChanged(bool focused) => onEditingChanged?.call(focused);
}

String _weightLabel(ExerciseKind kind, WeightUnit unit) {
  final base = unit == WeightUnit.kg ? 'Kg' : 'Lbs';
  return switch (kind) {
    ExerciseKind.assisted => 'Unterst. $base',
    ExerciseKind.bodyweightLoaded => '+$base',
    _ => base,
  };
}

/// Ergebnis einer Feldeingabe. `pending` bedeutet: noch unvollständig (etwa
/// „102,“), also weder gültig noch fehlerhaft.
typedef _Parsed<T> = ({T? value, String? error, bool pending});

typedef _Parser<T> = _Parsed<T> Function(
  String text, {
  required bool committing,
});

_Parsed<double> _parseWeight(
  String text,
  WeightUnit unit, {
  required bool committing,
}) {
  var input = text.trim();
  if (input.endsWith(',') || input.endsWith('.')) {
    if (!committing) return (value: null, error: null, pending: true);
    input = input.substring(0, input.length - 1);
  }
  try {
    return (value: parseWeightInput(input, unit), error: null, pending: false);
  } on FormatException {
    return (value: null, error: 'Kein gültiges Gewicht', pending: false);
  }
}

_Parsed<int> _parseRepetitions(String text) {
  try {
    return (value: parseRepetitionsInput(text), error: null, pending: false);
  } on FormatException {
    return (value: null, error: 'Nur ganze Zahlen', pending: false);
  }
}

_Parsed<int> _parseRir(String text) {
  try {
    return (value: parseRirInput(text), error: null, pending: false);
  } on FormatException {
    return (value: null, error: 'RIR von 0 bis $maxRir', pending: false);
  }
}

/// Satzlabel im Kreis. Ein Tipp übernimmt den Vorwert in leere Felder.
class _LabelCircle extends StatelessWidget {
  const _LabelCircle({
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final GainerColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Satz $label, Vorwert übernehmen',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.elevatedSurface,
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: GainerTypography.label.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Zahlenfeld mit kleinem grauem Label darüber. Der Wert wird beim Verlassen
/// des Feldes übernommen; ungültige Eingaben bleiben stehen und werden rot.
class _NumberInput<T> extends StatefulWidget {
  const _NumberInput({
    required this.label,
    required this.text,
    required this.keyboard,
    required this.focusNode,
    required this.parse,
    required this.format,
    required this.onCommit,
    required this.onFocusChanged,
    this.placeholder,
  });

  final String label;

  /// Gespeicherter Wert als Anzeigetext.
  final String text;
  final String? placeholder;
  final TextInputType keyboard;
  final FocusNode focusNode;
  final _Parser<T> parse;
  final String Function(T? value) format;
  final ValueChanged<T?> onCommit;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<_NumberInput<T>> createState() => _NumberInputState<T>();
}

class _NumberInputState<T> extends State<_NumberInput<T>> {
  final _controller = TextEditingController();
  String? _error;
  bool _focused = false;

  FocusNode get _focus => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.text;
    _focus.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_NumberInput<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      _focus.addListener(_handleFocusChanged);
    }
    // Während der Eingabe oder bei einem ungültigen Text bleibt der Text des
    // Nutzers stehen; sonst folgt das Feld dem gespeicherten Wert.
    if (!_focus.hasFocus && _error == null && _controller.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    // Der Fokusknoten gehört dem Screen und wird dort entsorgt.
    _focus.removeListener(_handleFocusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String text) {
    final result = widget.parse(text, committing: false);
    if (result.pending) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    if (_error != null) setState(() => _error = null);
    widget.onCommit(result.value);
  }

  void _handleFocusChanged() {
    widget.onFocusChanged(_focus.hasFocus);
    if (_focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
    if (_focus.hasFocus) return;
    final result = widget.parse(_controller.text, committing: true);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    if (_error != null) setState(() => _error = null);
    widget.onCommit(result.value);
    _controller.text = widget.format(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final placeholder = widget.placeholder;
    final showsPlaceholder = widget.text.isEmpty && placeholder != null;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: GainerTypography.caption.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: GainerSpacing.xxs),
        Semantics(
          label: widget.label,
          value: showsPlaceholder ? 'Vorwert $placeholder' : null,
          child: SizedBox(
            height: _fieldHeight,
            child: CupertinoTextField(
              controller: _controller,
              focusNode: _focus,
              keyboardType: widget.keyboard,
              placeholder: placeholder,
              placeholderStyle: GainerTypography.value.copyWith(
                color: colors.placeholderText,
              ),
              style: GainerTypography.value.copyWith(color: colors.primaryText),
              textAlignVertical: TextAlignVertical.center,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: _underline(colors, error: error != null),
              onChanged: _handleChanged,
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: GainerSpacing.xxs),
            child: Text(
              error,
              style: GainerTypography.caption.copyWith(
                color: colors.destructive,
              ),
            ),
          ),
      ],
    );
  }

  /// Werte stehen ohne Feldhintergrund und Rahmen. Den Fokus zeigt eine
  /// Akzentlinie darunter, ein Fehler eine rote.
  BoxDecoration _underline(GainerColors colors, {required bool error}) {
    final visible = error || _focused;
    return BoxDecoration(
      border: Border(
        bottom: visible
            ? BorderSide(
                color: error ? colors.destructive : colors.accent,
                width: 1.5,
              )
            : BorderSide.none,
      ),
    );
  }
}

/// Mindesthöhe des Tap-Ziels je Zahlenfeld und Notizzelle.
const _fieldHeight = 44.0;

/// Notizfeld eines Satzes. Antippen öffnet den Notizeditor.
class _NotesCell extends StatelessWidget {
  const _NotesCell({required this.notes, required this.onTap});

  final String? notes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final text = notes ?? '';
    return Semantics(
      button: true,
      label: 'Notizen',
      value: text.isEmpty ? null : text,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notizen',
              style: GainerTypography.caption.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.xxs),
            Container(
              width: double.infinity,
              height: _fieldHeight,
              alignment: Alignment.centerLeft,
              child: Text(
                text.isEmpty ? ' ' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
