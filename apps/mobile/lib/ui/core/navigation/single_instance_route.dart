import 'package:flutter/cupertino.dart';

/// Vollbild-Screens, die es nur einmal im Navigator geben darf.
///
/// Öffnet die App einen solchen Screen erneut, etwa über die Live Activity
/// oder nach einer Wartezeit hinter einem doppelt getippten Button, holt
/// [pushSingleInstance] den vorhandenen Screen nach vorn. Sonst läge darunter
/// eine zweite Instanz mit altem Stand, die beim Schließen wieder erscheint.
final Map<String, Route<Object?>> _openRoutes = {};

Future<T?> pushSingleInstance<T>(
  BuildContext context, {
  required String key,
  required WidgetBuilder builder,
  bool rootNavigator = true,
  bool fullscreenDialog = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: rootNavigator);
  final existing = _openRoutes[key];
  // Nur im selben Navigator nach vorn holen; popUntil fände den Screen in
  // einem anderen Navigator nicht und schlösse alles.
  if (existing != null &&
      existing.isActive &&
      identical(existing.navigator, navigator)) {
    navigator.popUntil((route) => route == existing);
    return Future<T?>.value();
  }
  final route = CupertinoPageRoute<T>(
    fullscreenDialog: fullscreenDialog,
    settings: RouteSettings(name: key),
    builder: builder,
  );
  _openRoutes[key] = route;
  return navigator.push<T>(route).whenComplete(() {
    if (identical(_openRoutes[key], route)) _openRoutes.remove(key);
  });
}
