import 'package:flutter/cupertino.dart';

import '../components/components.dart';
import '../theme.dart';
import '../view_models/mobile_shell_view_model.dart';

/// Hauptgerüst der Tabs: Inhalte oben, darunter der reservierte Slot und die schwebende Tableiste.
/// Tabs werden beim ersten Anzeigen gebaut und behalten danach ihren Zustand.
class MobileTabScaffold extends StatelessWidget {
  const MobileTabScaffold({
    required this.model,
    required this.tabBuilder,
    this.compactTrainingBar,
    super.key,
  });

  final MobileShellViewModel model;
  final Widget Function(BuildContext context, MobileArea area) tabBuilder;

  /// Reservierter Platz direkt über der Tableiste, etwa für die kompakte Trainingsleiste.
  final Widget? compactTrainingBar;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ColoredBox(
        color: GainerDesign.colorsOf(context).background,
        child: Column(
          children: [
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: _TabBodies(
                  currentIndex: model.selectedIndex,
                  tabBuilder: tabBuilder,
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GainerSpacing.m,
                  0,
                  GainerSpacing.m,
                  GainerSpacing.xs,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (compactTrainingBar case final bar?) ...[
                      bar,
                      const SizedBox(height: GainerSpacing.xs),
                    ],
                    GainerFloatingTabBar(
                      items: [
                        for (final area in MobileArea.values)
                          GainerTabItem(label: area.label, icon: area.icon),
                      ],
                      currentIndex: model.selectedIndex,
                      onTap: model.selectTab,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBodies extends StatefulWidget {
  const _TabBodies({required this.currentIndex, required this.tabBuilder});

  final int currentIndex;
  final Widget Function(BuildContext context, MobileArea area) tabBuilder;

  @override
  State<_TabBodies> createState() => _TabBodiesState();
}

class _TabBodiesState extends State<_TabBodies> {
  final _built = List.filled(MobileArea.values.length, false);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [for (final area in MobileArea.values) _tab(context, area)],
    );
  }

  Widget _tab(BuildContext context, MobileArea area) {
    final active = area.index == widget.currentIndex;
    _built[area.index] = _built[area.index] || active;
    return HeroMode(
      enabled: active,
      child: Offstage(
        offstage: !active,
        child: TickerMode(
          enabled: active,
          child: _built[area.index]
              ? Builder(builder: (context) => widget.tabBuilder(context, area))
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
