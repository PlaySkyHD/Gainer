import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

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
      builder: (context, model, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Coach')),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Frage zu deinem Training oder deiner Entwicklung',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navTitleTextStyle,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Der Coach nutzt serverseitig ausgewertete Daten. Antworten sind Hinweise, keine Änderungen an deinem Konto.',
                  ),
                  const SizedBox(height: 16),
                  CupertinoTextField(
                    controller: _question,
                    maxLength: 1000,
                    maxLines: 4,
                    placeholder: 'Zum Beispiel: Wie regelmäßig war mein Training zuletzt?',
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton.filled(
                    onPressed: model.isLoading
                        ? null
                        : () => model.ask(_question.text),
                    child: model.isLoading
                        ? const CupertinoActivityIndicator()
                        : const Text('Frage senden'),
                  ),
                  if (model.errorMessage case final error?)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ),
                  if (model.response case final answer?) ...[
                    const SizedBox(height: 24),
                    Text(
                      answer.summary,
                      style: CupertinoTheme.of(context).textTheme.textStyle
                          .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    for (final item in answer.observations)
                      _AnswerItem(text: item),
                    if (answer.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Mögliche nächste Schritte',
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .navTitleTextStyle,
                      ),
                      for (final item in answer.suggestions)
                        _AnswerItem(text: item),
                    ],
                    if (answer.dataGaps.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Für eine vollständigere Auswertung fehlen noch Daten:',
                      ),
                      for (final item in answer.dataGaps)
                        _AnswerItem(text: item),
                    ],
                    Text(
                      'Datengrundlage: Revision ${answer.asOfRevision}',
                      style: TextStyle(
                        color: GainerTheme.secondaryText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AnswerItem extends StatelessWidget {
  const _AnswerItem({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
