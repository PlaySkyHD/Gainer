import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Pläne-Segment. Die Planverwaltung folgt in einem eigenen Schritt und nutzt
/// dieses Widget als Einstiegspunkt.
class TrainingPlansSection extends StatelessWidget {
  const TrainingPlansSection({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  Widget build(BuildContext context) {
    return GainerCard(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Text(
        'Pläne erscheinen hier, sobald die Planverwaltung verfügbar ist.',
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(
          color: GainerDesign.colorsOf(context).secondaryText,
        ),
      ),
    );
  }
}
