import 'package:flutter/cupertino.dart';

/// Vollbild-Screens, die es nur einmal im Root-Navigator geben darf.
///
/// Öffnet die App einen solchen Screen erneut, etwa über die Live Activity,
/// während er schon offen ist, holt [pushSingleInstance] den vorhandenen
/// Screen nach vorn. Sonst läge darunter eine zweite Instanz mit altem Stand,
/// die beim Schließen wieder erscheint.
final Map<String, Route<void>> _openRoutes = {};

Future<void> pushSingleInstance(
  BuildContext context, {
  required String key,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final existing = _openRoutes[key];
  if (existing != null && existing.isActive) {
    navigator.popUntil((route) => route == existing);
    return Future<void>.value();
  }
  final route = CupertinoPageRoute<void>(
    fullscreenDialog: true,
    settings: RouteSettings(name: key),
    builder: builder,
  );
  _openRoutes[key] = route;
  return navigator.push<void>(route).whenComplete(() {
    if (identical(_openRoutes[key], route)) _openRoutes.remove(key);
  });
}
