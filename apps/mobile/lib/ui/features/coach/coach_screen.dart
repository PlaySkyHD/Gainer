import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api/api_models.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
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
