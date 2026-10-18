import 'package:flutter/cupertino.dart';

import '../../../domain/models/timer/rest_timer_sound.dart';
import '../../../domain/models/timer/rest_timer_state.dart';
import '../../core/components/gainer_grouped_section.dart';
import '../../core/components/gainer_list_row.dart';
import '../../core/components/gainer_sheet.dart';
import '../../core/theme.dart';
import 'rest_timer_controller.dart';
import 'rest_timer_format.dart';

/// Sheet „Timersound“: Liste der Töne mit Häkchen. Antippen spielt den Ton zur
/// Probe und wählt ihn; das Häkchen oben rechts schließt.
Future<void> showRestTimerSoundSheet(
  BuildContext context,
  RestTimerController controller,
) {
  return showGainerSheet<void>(
    context: context,
    builder: (_) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _OptionSheetBody(
        title: 'Timersound',
        children: [
          GainerGroupedSection(
            children: [
              for (final sound in RestTimerSound.all)
                GainerListRow(
                  title: sound.label,
                  trailing: sound.id == controller.soundId
                      ? Icon(
                          CupertinoIcons.checkmark,
                          size: 18,
                          color: GainerDesign.colorsOf(context).primaryText,
                        )
                      : null,
                  onTap: () => controller.selectSound(sound.id),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Sheet „Timer bearbeiten“: Shortcuts löschen, per Ziehgriff sortieren und
/// über die Minuten/Sekunden-Auswahl hinzufügen.
Future<void> showRestTimerEditSheet(
  BuildContext context,
  RestTimerController controller,
) {
  return showGainerSheet<void>(
    context: context,
    builder: (_) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _OptionSheetBody(
        title: 'Timer bearbeiten',
        children: [_ShortcutList(controller: controller)],
      ),
    ),
  );
}

/// Fragt die Dauer ab und legt einen neuen Shortcut an. Dauer außerhalb von
/// 5 s bis 30 min wird auf die Grenze gesetzt.
Future<void> addRestTimerShortcut(
  BuildContext context,
  RestTimerController controller,
) async {
  final picked = await showGainerSheet<Duration>(
    context: context,
    builder: (_) => const _DurationPickerSheet(),
  );
  if (picked == null) return;
  await controller.addShortcut(_clampShortcut(picked.inSeconds));
}

int _clampShortcut(int seconds) {
  if (seconds < restTimerMinSeconds) return restTimerMinSeconds;
  if (seconds > restTimerMaxSeconds) return restTimerMaxSeconds;
  return seconds;
}

/// Schlüssel des Häkchens oben rechts in den Unter-Sheets.
const restTimerOptionDoneKey = ValueKey('rest-timer-option-done');

/// Großer Titel links, Häkchen rechts oben, darunter scrollbarer Inhalt.
class _OptionSheetBody extends StatelessWidget {
  const _OptionSheetBody({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              GainerSpacing.xs,
              GainerSpacing.m,
              GainerSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GainerTypography.largeTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ),
                Semantics(
                  key: restTimerOptionDoneKey,
                  button: true,
                  label: 'Fertig',
                  excludeSemantics: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(
                      GainerRadii.iconButtonDiameter,
                    ),
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(
                      GainerRadii.iconButtonDiameter / 2,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(
                      CupertinoIcons.checkmark,
                      size: 22,
                      color: colors.onAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.m,
                0,
                GainerSpacing.m,
                GainerSpacing.m,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutList extends StatelessWidget {
  const _ShortcutList({required this.controller});

  final RestTimerController controller;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final shortcuts = controller.shortcuts.seconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(GainerRadii.field),
          ),
          child: ReorderableList(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: shortcuts.length,
            onReorderItem: controller.moveShortcut,
            itemBuilder: (context, index) => _ShortcutRow(
              key: ValueKey(shortcuts[index]),
              seconds: shortcuts[index],
              index: index,
              onDelete: () => controller.removeShortcut(shortcuts[index]),
            ),
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
        Semantics(
          button: true,
          label: 'Shortcut hinzufügen',
          excludeSemantics: true,
          child: CupertinoButton(
            minimumSize: const Size.square(44),
            onPressed: () => addRestTimerShortcut(context, controller),
            child: Icon(CupertinoIcons.plus, color: colors.accent),
          ),
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.seconds,
    required this.index,
    required this.onDelete,
    super.key,
  });

  final int seconds;
  final int index;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final label = formatRestTimerCountdown(seconds);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: '$label löschen',
              excludeSemantics: true,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(36),
                onPressed: onDelete,
                child: Icon(
                  CupertinoIcons.minus_circle_fill,
                  size: 24,
                  color: colors.destructive,
                ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: GainerTypography.timer.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Ziehen zum Umordnen',
                child: Padding(
                  padding: const EdgeInsets.all(GainerSpacing.xxs),
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    size: 22,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dauerwähler für neue Shortcuts im Bereich 5 s bis 30 min.
class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet();

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  var _value = const Duration(minutes: 3);

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return SizedBox(
      height: 320,
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GainerSpacing.s,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen', maxLines: 1),
                ),
              ),
              Expanded(
                child: Text(
                  'Timer hinzufügen',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GainerTypography.cardTitle.copyWith(
                    color: colors.primaryText,
                  ),
                ),
              ),
              Flexible(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GainerSpacing.s,
                  ),
                  onPressed: () => Navigator.of(context).pop(_value),
                  child: const Text('Hinzufügen', maxLines: 1),
                ),
              ),
            ],
          ),
          Expanded(
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.ms,
              initialTimerDuration: _value,
              minuteInterval: 1,
              secondInterval: 5,
              onTimerDurationChanged: (value) => _value = value,
            ),
          ),
        ],
      ),
    );
  }
}
