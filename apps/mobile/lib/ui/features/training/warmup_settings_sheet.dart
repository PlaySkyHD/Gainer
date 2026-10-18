import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'warmup_steps_editor.dart';
import 'workout_view_model.dart';

/// Sheet „Aufwärmhinweis“: Schalter, Standardstufen und Anzeige der
/// Wiederholungen. Änderungen werden sofort gespeichert.
Future<void> showWarmupSettingsSheet(
  BuildContext context,
  WorkoutViewModel viewModel,
) {
  return showGainerSheet<void>(
    context: context,
    builder: (_) => _WarmupSettingsBody(viewModel: viewModel),
  );
}

class _WarmupSettingsBody extends StatelessWidget {
  const _WarmupSettingsBody({required this.viewModel});

  final WorkoutViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GainerSheetHeader(title: 'Aufwärmhinweis'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) => _content(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final settings = viewModel.warmupSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerGroupedSection(
          footer:
              'Zeigt über dem ersten Arbeitssatz Gewichte zum Aufwärmen, '
              'gerechnet vom Vorwert. Der Hinweis wird nicht gespeichert.',
          children: [
            GainerListRow(
              title: 'Aufwärmhinweis',
              trailing: CupertinoSwitch(
                key: const ValueKey('warmup-enabled'),
                value: settings.enabled,
                onChanged: (value) => viewModel.setWarmupSettings(
                  viewModel.warmupSettings.copyWith(enabled: value),
                ),
              ),
            ),
          ],
        ),
        if (settings.enabled) ...[
          const SizedBox(height: GainerSpacing.m),
          const GainerSectionHeader(title: 'Standardstufen'),
          WarmupStepsEditor(
            initialSteps: settings.steps,
            onChanged: (steps) => viewModel.setWarmupSettings(
              viewModel.warmupSettings.copyWith(steps: steps),
            ),
          ),
          const SizedBox(height: GainerSpacing.s),
          GainerGroupedSection(
            children: [
              GainerListRow(
                title: 'Wiederholungen anzeigen',
                trailing: CupertinoSwitch(
                  key: const ValueKey('warmup-show-repetitions'),
                  value: settings.showRepetitions,
                  onChanged: (value) => viewModel.setWarmupSettings(
                    viewModel.warmupSettings.copyWith(showRepetitions: value),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
