import 'package:flutter/cupertino.dart';

import '../../core/components/components.dart';

/// Platzhalter bis zur neuen Trainings-UI. Der Tab bleibt sichtbar, zeigt aber
/// keine Trainingsdaten aus dem alten Modell.
class TrainingPlaceholderScreen extends StatelessWidget {
  const TrainingPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GainerScaffold(
      title: 'Training',
      children: [
        GainerCard(child: Text('Das Training wird gerade neu aufgebaut.')),
      ],
    );
  }
}
