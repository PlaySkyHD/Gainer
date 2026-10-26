import 'package:flutter/widgets.dart';

/// Schließt beim Einblenden alle Routen, die im Root-Navigator über dem
/// Zuhause-Screen liegen.
///
/// Vollbilder (Training, Cardio) und Sheets liegen im Root-Navigator und
/// überleben den Wechsel des Zuhause-Screens. Läuft die Sitzung ab, bliebe
/// sonst ein offener Trainingsscreen über dem Login stehen und speicherte
/// gegen das geschlossene Konto.
class PopRoutesOnMount extends StatefulWidget {
  const PopRoutesOnMount({required this.child, super.key});

  final Widget child;

  @override
  State<PopRoutesOnMount> createState() => _PopRoutesOnMountState();
}

class _PopRoutesOnMountState extends State<PopRoutesOnMount> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
