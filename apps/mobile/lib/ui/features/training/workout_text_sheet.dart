import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Editor für Titel und Notizen. Liefert den getrimmten Text, einen leeren
/// Text zum Leeren und `null` bei Abbruch.
Future<String?> showWorkoutTextSheet({
  required BuildContext context,
  required String title,
  required String initialText,
  String placeholder = '',
  bool multiline = false,
  int maxLength = 2000,
  String? Function(String text)? validate,
}) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (_) => _WorkoutTextSheet(
      title: title,
      initialText: initialText,
      placeholder: placeholder,
      multiline: multiline,
      maxLength: maxLength,
      validate: validate,
    ),
  );
}

/// Gerundetes Sheet mit Titel, Textfeld, Fehlertext und „Fertig“.
class _WorkoutTextSheet extends StatefulWidget {
  const _WorkoutTextSheet({
    required this.title,
    required this.initialText,
    required this.placeholder,
    required this.multiline,
    required this.maxLength,
    required this.validate,
  });

  final String title;
  final String initialText;
  final String placeholder;
  final bool multiline;
  final int maxLength;
  final String? Function(String text)? validate;

  @override
  State<_WorkoutTextSheet> createState() => _WorkoutTextSheetState();
}

class _WorkoutTextSheetState extends State<_WorkoutTextSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    final error =
        widget.validate?.call(text) ??
        (text.length > widget.maxLength
            ? 'Der Text darf höchstens ${widget.maxLength} Zeichen haben.'
            : null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GainerRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(GainerSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Abbrechen',
                      style: GainerTypography.body.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: GainerTypography.title.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
              const SizedBox(height: GainerSpacing.m),
              CupertinoTextField(
                controller: _controller,
                autofocus: true,
                placeholder: widget.placeholder,
                placeholderStyle: GainerTypography.value.copyWith(
                  color: colors.placeholderText,
                ),
                style: GainerTypography.value.copyWith(
                  color: colors.primaryText,
                ),
                minLines: widget.multiline ? 4 : 1,
                maxLines: widget.multiline ? 8 : 1,
                padding: const EdgeInsets.all(GainerSpacing.s),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(GainerRadii.field),
                  border: _error == null
                      ? null
                      : Border.all(color: colors.destructive, width: 1.5),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: GainerSpacing.xs),
                  child: Text(
                    error,
                    style: GainerTypography.label.copyWith(
                      color: colors.destructive,
                    ),
                  ),
                ),
              const SizedBox(height: GainerSpacing.m),
              GainerPillButton(label: 'Fertig', expand: true, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
