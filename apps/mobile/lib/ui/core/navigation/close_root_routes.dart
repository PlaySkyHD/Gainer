import 'package:flutter/widgets.dart';

/// Merkt sich die Routen des Root-Navigators, um alle über der ersten ohne
/// Animation entfernen zu können.
///
/// Vollbilder (Training, Cardio) und Sheets liegen im Root-Navigator und
/// überleben den Wechsel des Zuhause-Screens. Sie müssen weg sein, bevor ein
/// Konto-Scope entsorgt wird, sonst bauen oder entsorgen sie sich gegen ihn.
class RootRouteCloser extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) _routes.remove(oldRoute);
    if (newRoute != null) {
      _routes.insert(index >= 0 ? index : _routes.length, newRoute);
    }
  }

  /// Entfernt alle Routen über der ersten und wartet, bis ihre Widgets
  /// entsorgt sind.
  Future<void> closeAll() async {
    final navigator = this.navigator;
    if (navigator == null || _routes.length <= 1) return;
    for (final route in _routes.skip(1).toList().reversed) {
      navigator.removeRoute(route);
    }
    await WidgetsBinding.instance.endOfFrame;
  }
}
