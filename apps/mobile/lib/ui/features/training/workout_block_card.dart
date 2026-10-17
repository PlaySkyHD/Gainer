import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Übergangsdarstellung eines Übungsblocks: Name und Satzanzahl. Wird durch die
/// vollständige Übungskarte mit Satzzeilen ersetzt.
class WorkoutBlockCard extends StatelessWidget {
  const WorkoutBlockCard({required this.block, super.key});

  final WorkoutBlock block;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final count = block.sets.length;
    return GainerCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              block.exerciseNameSnapshot,
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
          ),
          Text(
            count == 1 ? '1 Satz' : '$count Sätze',
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}
