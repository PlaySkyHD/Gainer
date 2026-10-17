import 'dart:math' show max;

import 'package:flutter/cupertino.dart';

import '../components/components.dart';
import '../theme.dart';
import '../view_models/mobile_shell_view_model.dart';

/// Hauptgerüst der Tabs: Inhalte oben, darunter der reservierte Slot und die schwebende Tableiste.
/// Tabs werden beim ersten Anzeigen gebaut und behalten danach ihren Zustand.
class MobileTabScaffold extends StatefulWidget {
  const MobileTabScaffold({
    required this.model,
    required this.tabBuilder,
    this.compactTrainingBar,
    super.key,
  });

  final MobileShellViewModel model;
  final Widget Function(BuildContext context, MobileArea area) tabBuilder;

  /// Reservierter Platz direkt über der Tableiste, etwa für die kompakte Trainingsleiste.
  /// Der Slot liefert seinen Abstand selbst, damit er ohne Inhalt keinen Platz belegt.
  final Widget? compactTrainingBar;

  @override
  State<MobileTabScaffold> createState() => _MobileTabScaffoldState();
}

class _MobileTabScaffoldState extends State<MobileTabScaffold> {
  final _bottomKey = GlobalKey();

  /// Höhe von Slot und Tableiste. Der Inhalt endet bereits darüber, daher darf die
  /// Tastatur nur den Rest der Höhe verdecken.
  double _bottomHeight = 0;

  void _measureBottom() {
    final box = _bottomKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.hasSize == true ? box!.size.height : 0.0;
    if (mounted && height != _bottomHeight) {
      setState(() => _bottomHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottom());
    final mediaQuery = MediaQuery.of(context);
    final keyboard = mediaQuery.viewInsets.bottom;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => ColoredBox(
        color: GainerDesign.colorsOf(context).background,
        child: Column(
          children: [
            Expanded(
              child: MediaQuery(
                data: mediaQuery
                    .removePadding(removeBottom: true)
                    .copyWith(
                      viewInsets: mediaQuery.viewInsets.copyWith(
                        bottom: max(0, keyboard - _bottomHeight),
                      ),
                    ),
                child: _TabBodies(
                  currentIndex: widget.model.selectedIndex,
                  tabBuilder: widget.tabBuilder,
                ),
              ),
            ),
            // Ändert sich die Höhe des Bereichs (z. B. wenn die Trainingsleiste
            // erscheint), wird nach dem Frame neu gemessen, damit der Tastatur-
            // Abstand stimmt.
            NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _measureBottom(),
                );
                return true;
              },
              child: SizeChangedLayoutNotifier(
                child: KeyedSubtree(
                  key: _bottomKey,
                  child: SafeArea(
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
                          ?widget.compactTrainingBar,
                          GainerFloatingTabBar(
                            items: [
                              for (final area in MobileArea.values)
                                GainerTabItem(
                                  label: area.label,
                                  icon: area.icon,
                                ),
                            ],
                            currentIndex: widget.model.selectedIndex,
                            onTap: widget.model.selectTab,
                          ),
                        ],
                      ),
                    ),
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
