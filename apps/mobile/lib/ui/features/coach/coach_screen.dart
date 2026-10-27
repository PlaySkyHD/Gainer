import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api/api_models.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'coach_memory_screen.dart';
import 'coach_view_model.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({required this.viewModel, super.key});
  final CoachViewModel viewModel;
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _question = TextEditingController();
  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.viewModel,
    child: Consumer<CoachViewModel>(
      builder: (context, model, _) {
        final colors = GainerDesign.colorsOf(context);
        return GainerScaffold(
          title: 'Coach',
          trailing: [
            if (model.memories case final memories?)
              GainerToolbarButton(
                key: const ValueKey('coach-open-memory'),
                icon: CupertinoIcons.bookmark,
                semanticLabel: 'Gedächtnis',
                onPressed: () async {
                  await Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => CoachMemoryScreen(
                        repository: memories,
                        // Aktueller Stand statt Zustand beim Öffnen des
                        // Kontos; der Screen bietet selbst „Erneut laden“.
                        online: !model.memoryOffline,
                      ),
                    ),
                  );
                  // Dort gelöschte Notizen machen wieder Platz zum Merken.
                  await model.refreshMemoryUsage();
                },
              ),
          ],
          children: [
            GainerGroupedSection(
              header: 'Frage zu deinem Training oder deiner Entwicklung',
              footer: 'Der Coach nutzt serverseitig ausgewertete Daten. Antworten sind Hinweise, keine Änderungen an deinem Konto.',
              children: [
                CupertinoTextField(
                  controller: _question,
                  maxLength: 1000,
                  maxLines: 4,
                  placeholder:
                      'Zum Beispiel: Wie regelmäßig war mein Training zuletzt?',
                  style: GainerTypography.body.copyWith(
                    color: colors.primaryText,
                  ),
                  placeholderStyle: GainerTypography.body.copyWith(
                    color: colors.placeholderText,
                  ),
                  padding: const EdgeInsets.all(GainerSpacing.m),
                  decoration: const BoxDecoration(),
                ),
                if (model.errorMessage case final error?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      GainerSpacing.m,
                      0,
                      GainerSpacing.m,
                      GainerSpacing.m,
                    ),
                    child: Text(
                      error,
                      style: GainerTypography.body.copyWith(
                        color: colors.destructive,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: GainerSpacing.m),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: colors.accent,
                disabledColor: colors.elevatedSurface,
                borderRadius: GainerRadii.pill,
                onPressed: model.isLoading
                    ? null
                    : () => model.ask(_question.text),
                child: model.isLoading
                    ? CupertinoActivityIndicator(color: colors.primaryText)
                    : Text(
                        'Frage senden',
                        style: GainerTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onAccent,
                        ),
                      ),
              ),
            ),
            if (model.response case final answer?) ...[
              const SizedBox(height: GainerSpacing.l),
              ..._answerSections(context, answer),
            ],
          ],
        );
      },
    ),
  );

  List<int> _visibleSuggestions(ApiCoachResponse answer) => [
    for (var i = 0; i < answer.memorySuggestions.length; i++)
      if (widget.viewModel.suggestionState(i) != CoachSuggestionState.dismissed)
        i,
  ];

  List<Widget> _answerSections(BuildContext context, ApiCoachResponse answer) {
    final colors = GainerDesign.colorsOf(context);
    return [
      GainerGroupedSection(
        header: 'Antwort',
        footer: 'Datengrundlage: Revision ${answer.asOfRevision}',
        children: [
          Padding(
            padding: const EdgeInsets.all(GainerSpacing.m),
            child: Text(
              answer.summary,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
          ),
          for (final item in answer.observations) _AnswerItem(text: item),
        ],
      ),
      if (_visibleSuggestions(answer) case final indexes
          when indexes.isNotEmpty && widget.viewModel.memories != null) ...[
        const SizedBox(height: GainerSpacing.l),
        _memorySection(colors, answer, indexes),
      ],
      if (answer.suggestions.isNotEmpty) ...[
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Mögliche nächste Schritte',
          children: [
            for (final item in answer.suggestions) _AnswerItem(text: item),
          ],
        ),
      ],
      if (answer.dataGaps.isNotEmpty) ...[
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          children: [
            Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Text(
                'Für eine vollständigere Auswertung fehlen noch Daten:',
                style: GainerTypography.body.copyWith(color: colors.warning),
              ),
            ),
            for (final item in answer.dataGaps) _AnswerItem(text: item),
          ],
        ),
      ],
    ];
  }

  Widget _memorySection(
    GainerColors colors,
    ApiCoachResponse answer,
    List<int> indexes,
  ) => GainerGroupedSection(
    header: 'Merken?',
    footer:
        'Der Coach speichert nichts von selbst. Gemerkte Notizen '
        'findest du oben rechts unter Gedächtnis.',
    children: [
      for (final index in indexes)
        _MemorySuggestionRow(
          key: ValueKey('coach-suggestion-$index'),
          suggestion: answer.memorySuggestions[index],
          state: widget.viewModel.suggestionState(index),
          error: widget.viewModel.suggestionError(index),
          onRemember: widget.viewModel.rememberBlockedReason == null
              ? () => widget.viewModel.remember(index)
              : null,
          onDismiss: () => widget.viewModel.dismiss(index),
        ),
      // Sperrgrund und „Erneut prüfen“ nur, solange etwas zu merken ist.
      if (widget.viewModel.rememberBlockedReason case final reason?
          when widget.viewModel.hasOpenSuggestions)
        Padding(
          padding: const EdgeInsets.all(GainerSpacing.m),
          child: Text(
            reason,
            key: const ValueKey('coach-remember-blocked'),
            style: GainerTypography.body.copyWith(color: colors.warning),
          ),
        ),
      if (widget.viewModel.memoryOffline && widget.viewModel.hasOpenSuggestions)
        GainerListRow(
          key: const ValueKey('coach-remember-retry'),
          title: 'Erneut prüfen',
          leadingIcon: CupertinoIcons.arrow_clockwise,
          onTap: widget.viewModel.refreshMemoryUsage,
        ),
    ],
  );
}

/// Ein Vorschlag mit „Merken“ und „Verwerfen“, nach dem Speichern als gemerkt.
class _MemorySuggestionRow extends StatelessWidget {
  const _MemorySuggestionRow({
    required this.suggestion,
    required this.state,
    required this.error,
    required this.onRemember,
    required this.onDismiss,
    super.key,
  });

  final ApiCoachMemorySuggestion suggestion;
  final CoachSuggestionState state;
  final String? error;

  /// Null, wenn „Merken“ gerade nicht geht; der Abschnitt nennt den Grund.
  final VoidCallback? onRemember;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final saved = state == CoachSuggestionState.saved;
    final saving = state == CoachSuggestionState.saving;
    return Padding(
      padding: const EdgeInsets.all(GainerSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            suggestion.category.label,
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: GainerSpacing.xxs),
          Text(
            suggestion.text,
            style: GainerTypography.body.copyWith(color: colors.primaryText),
          ),
          const SizedBox(height: GainerSpacing.s),
          if (saved)
            Row(
              children: [
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 18,
                  color: colors.accent,
                ),
                const SizedBox(width: GainerSpacing.xs),
                Flexible(
                  child: Text(
                    'Gemerkt',
                    style: GainerTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: GainerSpacing.xs,
              runSpacing: GainerSpacing.xs,
              children: [
                GainerPillButton(
                  label: 'Merken',
                  icon: CupertinoIcons.bookmark,
                  isLoading: saving,
                  onPressed: onRemember,
                ),
                GainerPillButton(
                  label: 'Verwerfen',
                  variant: GainerPillVariant.tonal,
                  onPressed: saving ? null : onDismiss,
                ),
              ],
            ),
          if (error case final message?) ...[
            const SizedBox(height: GainerSpacing.xs),
            Text(
              message,
              style: GainerTypography.label.copyWith(color: colors.destructive),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerItem extends StatelessWidget {
  const _AnswerItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      GainerSpacing.xs,
      GainerSpacing.m,
      GainerSpacing.xs,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '•  ',
          style: GainerTypography.body.copyWith(
            color: GainerDesign.colorsOf(context).primaryText,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: GainerTypography.body.copyWith(
              color: GainerDesign.colorsOf(context).primaryText,
            ),
          ),
        ),
      ],
    ),
  );
}
