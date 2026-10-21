import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/muscle_suggestion_service.dart';
import '../../../data/services/api/api_client.dart';
import '../../../domain/models/training/muscle_ai.dart';
import '../../../domain/models/training/muscles.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'body_map.dart';
import 'muscle_map_widgets.dart';

/// Ermittelt die Muskeln einer Übung im Dialog mit der KI. Liefert den
/// übernommenen Vorschlag oder `null`.
Future<MuscleAiSuggestion?> showMuscleAiSheet(
  BuildContext context, {
  required MuscleSuggestionService service,
  required String name,
  required ExerciseKind kind,
  String? notes,
}) {
  return showGainerSheet<MuscleAiSuggestion>(
    context: context,
    heightFactor: 0.85,
    builder: (_) =>
        _MuscleAiSheet(service: service, name: name, kind: kind, notes: notes),
  );
}

/// Verständliche Meldung für Fehler der KI-Anfrage.
String muscleAiErrorMessage(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'daily_budget_exhausted' =>
        'Das Tageslimit für KI-Anfragen ist erreicht. Morgen geht es wieder.',
      'network_error' => 'Keine Verbindung. Die KI braucht Internet.',
      _ =>
        'Die KI ist gerade nicht erreichbar. Versuche es gleich noch einmal.',
    };
  }
  return 'Die KI hat keine brauchbare Antwort geliefert. Versuche es noch einmal.';
}

class _MuscleAiSheet extends StatefulWidget {
  const _MuscleAiSheet({
    required this.service,
    required this.name,
    required this.kind,
    this.notes,
  });

  final MuscleSuggestionService service;
  final String name;
  final ExerciseKind kind;
  final String? notes;

  @override
  State<_MuscleAiSheet> createState() => _MuscleAiSheetState();
}

class _MuscleAiSheetState extends State<_MuscleAiSheet> {
  final _turns = <MuscleAiTurn>[];
  final _answerController = TextEditingController();
  MuscleAiReply? _reply;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reply = await widget.service.suggest(
        name: widget.name,
        kind: widget.kind,
        notes: widget.notes,
        turns: List.unmodifiable(_turns),
      );
      if (!mounted) return;
      setState(() => _reply = reply);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = muscleAiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _answer(String question, String answer) {
    final text = answer.trim();
    if (text.isEmpty) return;
    _turns.add(MuscleAiTurn(question: question, answer: text));
    _answerController.clear();
    _ask();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GainerSheetHeader(title: 'Muskeln mit KI'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(GainerSpacing.m),
            children: _content(context),
          ),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final intro = Text(
      '„${widget.name}“',
      textAlign: TextAlign.center,
      style: GainerTypography.cardTitle.copyWith(color: colors.primaryText),
    );
    if (_loading) {
      return [
        intro,
        const SizedBox(height: GainerSpacing.l),
        const Center(child: CupertinoActivityIndicator()),
        const SizedBox(height: GainerSpacing.s),
        Text(
          'Die KI überlegt …',
          textAlign: TextAlign.center,
          style: GainerTypography.caption.copyWith(color: colors.secondaryText),
        ),
      ];
    }
    if (_error case final message?) {
      return [
        intro,
        const SizedBox(height: GainerSpacing.m),
        Text(
          message,
          key: const ValueKey('muscle-ai-error'),
          textAlign: TextAlign.center,
          style: GainerTypography.body.copyWith(color: colors.destructive),
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerPillButton(
          key: const ValueKey('muscle-ai-retry'),
          label: 'Erneut versuchen',
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: _ask,
        ),
      ];
    }
    return switch (_reply) {
      MuscleAiQuestion(:final question, :final options) => [
        intro,
        const SizedBox(height: GainerSpacing.m),
        GainerCard(
          child: Text(
            question,
            key: const ValueKey('muscle-ai-question'),
            style: GainerTypography.body.copyWith(color: colors.primaryText),
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
        GainerGroupedSection(
          children: [
            for (final (index, option) in options.indexed)
              GainerListRow(
                key: ValueKey('muscle-ai-option-$index'),
                title: option,
                showChevron: true,
                onTap: () => _answer(question, option),
              ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        CupertinoTextField(
          key: const ValueKey('muscle-ai-answer'),
          controller: _answerController,
          placeholder: 'Oder eigene Antwort',
          maxLength: 300,
          placeholderStyle: GainerTypography.body.copyWith(
            color: colors.placeholderText,
          ),
          style: GainerTypography.body.copyWith(color: colors.primaryText),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(GainerRadii.field),
          ),
          onSubmitted: (value) => _answer(question, value),
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerPillButton(
          key: const ValueKey('muscle-ai-send'),
          label: 'Antworten',
          expand: true,
          onPressed: () => _answer(question, _answerController.text),
        ),
      ],
      MuscleAiSuggestion(
        :final primary,
        :final secondary,
        :final explanation,
      ) =>
        [
          intro,
          const SizedBox(height: GainerSpacing.m),
          GainerCard(
            child: Center(
              child: SizedBox(
                height: 200,
                child: BodyMap(
                  fills: roleFills(primary, secondary, colors),
                  semanticLabel:
                      'Vorschlag: Hauptmuskeln ${_names(primary)}, '
                      'Hilfsmuskeln ${_names(secondary)}',
                ),
              ),
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          GainerGroupedSection(
            footer: explanation.isEmpty ? null : explanation,
            children: [
              GainerListRow(
                key: const ValueKey('muscle-ai-primary'),
                title: 'Hauptmuskeln',
                value: _names(primary),
              ),
              GainerListRow(
                key: const ValueKey('muscle-ai-secondary'),
                title: 'Hilfsmuskeln',
                value: _names(secondary),
              ),
            ],
          ),
          const SizedBox(height: GainerSpacing.m),
          GainerPillButton(
            key: const ValueKey('muscle-ai-apply'),
            label: 'Übernehmen',
            expand: true,
            onPressed: () => Navigator.of(context).pop(_reply),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Du kannst die Muskeln danach im Editor noch anpassen.',
            textAlign: TextAlign.center,
            style: GainerTypography.caption.copyWith(
              color: colors.secondaryText,
            ),
          ),
        ],
      null => [intro],
    };
  }

  static String _names(List<Muscle> muscles) => muscles.isEmpty
      ? 'Keine'
      : muscles.map((muscle) => muscle.label).join(', ');
}
