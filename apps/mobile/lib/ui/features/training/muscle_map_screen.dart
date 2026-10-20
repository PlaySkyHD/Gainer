import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/muscles.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'muscle_map_view_model.dart';
import 'muscle_map_widgets.dart';

Future<void> openMuscleMap(
  BuildContext context, {
  required TrainingLogRepository repository,
  String? planId,
}) {
  return Navigator.of(context).push<void>(
    CupertinoPageRoute<void>(
      builder: (_) =>
          MuscleMapScreen(repository: repository, initialPlanId: planId),
    ),
  );
}

/// Muskelübersicht: geplante Sätze aller oder eines Plans oder trainierte
/// Sätze eines Zeitraums als Körperkarte und Liste (Design D6).
class MuscleMapScreen extends StatefulWidget {
  const MuscleMapScreen({
    required this.repository,
    this.initialPlanId,
    super.key,
  });

  final TrainingLogRepository repository;
  final String? initialPlanId;

  @override
  State<MuscleMapScreen> createState() => _MuscleMapScreenState();
}

class _MuscleMapScreenState extends State<MuscleMapScreen> {
  late final MuscleMapViewModel _viewModel = MuscleMapViewModel(
    repository: widget.repository,
    initialPlanId: widget.initialPlanId,
  )..load();

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _pickPlan() async {
    const all = '';
    final picked = await showGainerActionSheet<String>(
      context: context,
      title: 'Plan',
      groups: [
        [
          const GainerSheetAction(
            label: 'Alle Pläne',
            icon: CupertinoIcons.square_stack_3d_up,
            value: all,
          ),
          for (final plan in _viewModel.plans)
            GainerSheetAction(
              label: plan.name,
              icon: CupertinoIcons.list_bullet,
              value: plan.planId,
            ),
        ],
      ],
    );
    if (picked == null) return;
    _viewModel.selectPlan(picked == all ? null : picked);
  }

  void _openMuscle(Muscle muscle) =>
      showMuscleDetailSheet(context, muscle: muscle, volume: _viewModel.volume);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => GainerScaffold(
        title: 'Muskeln',
        onRefresh: _viewModel.load,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final model = _viewModel;
    if (model.isLoading && !model.hasLoaded) {
      return const [Center(child: CupertinoActivityIndicator())];
    }
    if (model.errorMessage case final message? when !model.hasLoaded) {
      return [
        GainerCard(
          child: Text(
            message,
            style: GainerTypography.body.copyWith(color: colors.destructive),
          ),
        ),
      ];
    }
    final volume = model.volume;
    final planned = model.source == MuscleMapSource.planned;
    return [
      GainerSegmentedControl<MuscleMapSource>(
        options: const {
          MuscleMapSource.planned: 'Geplant',
          MuscleMapSource.trained: 'Trainiert',
        },
        value: model.source,
        onChanged: model.setSource,
      ),
      const SizedBox(height: GainerSpacing.s),
      if (planned)
        GainerGroupedSection(
          children: [
            GainerListRow(
              key: const ValueKey('muscle-map-plan'),
              title: 'Plan',
              value: model.selectedPlan?.name ?? 'Alle Pläne',
              showChevron: true,
              onTap: model.plans.isEmpty ? null : _pickPlan,
            ),
          ],
        )
      else
        GainerSegmentedControl<MuscleMapPeriod>(
          options: const {
            MuscleMapPeriod.week: '7 Tage',
            MuscleMapPeriod.fourWeeks: 'Ø 28 Tage',
          },
          value: model.period,
          onChanged: model.setPeriod,
        ),
      const SizedBox(height: GainerSpacing.m),
      MuscleVolumeCard(volume: volume, onMuscleTap: _openMuscle),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          GainerSpacing.m,
          GainerSpacing.xs,
          GainerSpacing.m,
          0,
        ),
        child: Text(
          _explanation(model),
          style: GainerTypography.caption.copyWith(color: colors.secondaryText),
        ),
      ),
      if (volume.exercisesWithoutMuscles.isNotEmpty) ...[
        const SizedBox(height: GainerSpacing.m),
        _MissingMusclesHint(names: volume.exercisesWithoutMuscles),
      ],
      const SizedBox(height: GainerSpacing.m),
      GainerGroupedSection(
        header: 'Sätze je Muskel',
        children: [
          for (final muscle in volume.ranked)
            GainerListRow(
              key: ValueKey('muscle-row-${muscle.name}'),
              title: muscle.label,
              value: volume.setsFor(muscle) > 0
                  ? formatMuscleSets(volume.setsFor(muscle))
                  : 'Nicht trainiert',
              showChevron: true,
              onTap: () => _openMuscle(muscle),
            ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
    ];
  }

  String _explanation(MuscleMapViewModel model) {
    const half = 'Hilfsmuskeln zählen einen halben Satz.';
    if (model.source == MuscleMapSource.planned) {
      return model.selectedPlan == null
          ? 'Arbeitssätze aller aktiven Pläne, jeder Plan einmal. $half'
          : 'Arbeitssätze dieses Plans. $half';
    }
    return model.period == MuscleMapPeriod.week
        ? 'Erfasste Arbeitssätze der letzten 7 Tage. $half'
        : 'Erfasste Arbeitssätze der letzten 28 Tage, Ø pro Woche. $half';
  }
}

class _MissingMusclesHint extends StatelessWidget {
  const _MissingMusclesHint({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final count = names.length;
    return GainerCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            color: colors.warning,
            size: 20,
          ),
          const SizedBox(width: GainerSpacing.xs),
          Expanded(
            child: Text(
              '${count == 1 ? '1 Übung hat' : '$count Übungen haben'} keine '
              'Muskeln und ${count == 1 ? 'fehlt' : 'fehlen'} in der Karte: '
              '${names.join(', ')}. Ergänze sie im Übungseditor.',
              style: GainerTypography.caption.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
