import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Statistik-Segment. Die Auswertung folgt in einem eigenen Schritt und nutzt
/// dieses Widget als Einstiegspunkt.
class TrainingStatisticsSection extends StatelessWidget {
  const TrainingStatisticsSection({required this.repository, super.key});

  final TrainingLogRepository repository;

  @override
  Widget build(BuildContext context) {
    return GainerCard(
      padding: const EdgeInsets.all(GainerSpacing.l),
      child: Text(
        'Statistiken erscheinen hier, sobald die Auswertung verfügbar ist.',
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(
          color: GainerDesign.colorsOf(context).secondaryText,
        ),
      ),
    );
  }
}
