import 'package:flutter/cupertino.dart';

import '../../../../data/repositories/health/health_review_coordinator.dart';
import '../../../../data/services/platform/platform_ports.dart';
import '../../../core/components/components.dart';
import '../../../core/theme.dart';
import 'health_review_view_model.dart';

class HealthReviewScreen extends StatefulWidget {
  const HealthReviewScreen({super.key, required this.viewModel});
  final HealthReviewViewModel viewModel;

  @override
  State<HealthReviewScreen> createState() => _HealthReviewScreenState();
}

class _HealthReviewScreenState extends State<HealthReviewScreen> {
  late final TextEditingController _from;
  late final TextEditingController _to;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = TextEditingController(
      text: _date(today.subtract(const Duration(days: 6))),
    );
    _to = TextEditingController(text: _date(today));
    widget.viewModel.load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final review = vm.review;
      return GainerScaffold(
        title: 'Apple Health',
        children: [
          _notice(
            context,
            'Health-Daten werden nur nach deiner Aktion geprüft. Leere Ergebnisse sagen nicht aus, ob der Zugriff verweigert wurde.',
          ),
          GainerGroupedSection(
            header: 'Gewicht übernehmen',
            children: [
              _field(context, _from, 'Von (JJJJ-MM-TT)'),
              _field(context, _to, 'Bis (JJJJ-MM-TT)'),
            ],
          ),
          const SizedBox(height: GainerSpacing.s),
          GainerPillButton(
            label: 'Health-Proben laden',
            expand: true,
            onPressed: vm.isLoading
                ? null
                : () => vm.prepareReview(
                    fromLocalDate: _from.text,
                    toLocalDate: _to.text,
                  ),
          ),
          if (review != null) ..._reviewChildren(context, vm, review),
          if (vm.lastResults.isNotEmpty) ..._importStatusChildren(context, vm),
          if (vm.errorMessage != null)
            _notice(context, vm.errorMessage!, isError: true),
          ..._workoutExportChildren(context, vm),
          if (vm.isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CupertinoActivityIndicator()),
            ),
        ],
      );
    },
  );

  List<Widget> _reviewChildren(
    BuildContext context,
    HealthReviewViewModel vm,
    HealthWeightReview review,
  ) => [
    _notice(
      context,
      'Prüfe Gewicht, Messzeit und Quelle. Erst bestätigte Einträge werden an den Gainer-Sync vorgemerkt.',
    ),
    if (review.samples.isEmpty)
      GainerGroupedSection(
        children: [
          _dataCard(
            context,
            'Keine Werte im Zeitraum gefunden.',
            'Das bedeutet nicht automatisch, dass der Zugriff verweigert wurde.',
          ),
        ],
      ),
    GainerGroupedSection(
      children: [
        for (final sample in review.samples)
          _switchRow(
            context,
            title: '${sample.weightKilograms.toStringAsFixed(2)} kg',
            detail:
                '${_localTime(sample.measuredAtUtc)} · ${sample.sourceName}',
            value: vm.selectedProbeIds.contains(sample.uuid),
            onChanged: (value) => vm.selectSample(sample.uuid, value),
          ),
        _switchRow(
          context,
          title: 'Ich bestätige, dass ausgewählte Check-ins zu meinem Gainer-Konto synchronisiert werden können.',
          value: vm.serverSyncNoticeAccepted,
          enabled: vm.selectedProbeIds.isNotEmpty,
          onChanged: vm.acceptServerSyncNotice,
        ),
      ],
    ),
    const SizedBox(height: GainerSpacing.s),
    Row(
      children: [
        Expanded(
          child: GainerPillButton(
            label: 'Prüfung abbrechen',
            variant: GainerPillVariant.tonal,
            onPressed: vm.cancelReview,
          ),
        ),
        const SizedBox(width: GainerSpacing.xs),
        Expanded(
          child: GainerPillButton(
            label: 'Auswahl übernehmen',
            onPressed:
                vm.isLoading ||
                    !vm.serverSyncNoticeAccepted ||
                    vm.selectedProbeIds.isEmpty
                ? null
                : _confirmImport,
          ),
        ),
      ],
    ),
  ];

  List<Widget> _importStatusChildren(
    BuildContext context,
    HealthReviewViewModel vm,
  ) => [
    GainerGroupedSection(
      header: 'Importstatus',
      children: [
        for (final result in vm.lastResults)
          _dataCard(
            context,
            _status(result.status),
            '${result.sample.weightKilograms.toStringAsFixed(2)} kg · ${_localTime(result.sample.measuredAtUtc)}',
          ),
      ],
    ),
  ];

  List<Widget> _workoutExportChildren(
    BuildContext context,
    HealthReviewViewModel vm,
  ) => [
    GainerGroupedSection(
      header: 'Abgeschlossene Workouts exportieren',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GainerSpacing.m,
            GainerSpacing.xs,
            GainerSpacing.m,
            GainerSpacing.xs,
          ),
          child: Text(
            'Nur serverbestätigte eigene Workouts werden angeboten. Es werden keine geschätzten Kalorien oder Pulswerte ergänzt.',
            style: GainerTypography.label.copyWith(
              color: GainerDesign.colorsOf(context).secondaryText,
            ),
          ),
        ),
        if (vm.completedWorkouts.isEmpty)
          _dataCard(
            context,
            'Keine serverbestätigten abgeschlossenen Workouts verfügbar.',
            '',
          ),
        for (final workout in vm.completedWorkouts)
          _actionCard(
            context,
            title: workout.value.title,
            detail:
                '${_localTime(workout.value.startedAtUtc)} · ${_localTime(workout.value.endedAtUtc!)}',
            actionLabel: 'Workout nach Apple Health exportieren',
            icon: CupertinoIcons.arrow_up_doc,
            onPressed: vm.isLoading ? null : () => _export(workout),
          ),
      ],
    ),
  ];

  Future<void> _confirmImport() async {
    final results = await widget.viewModel.confirmImport();
    if (!mounted) return;
    final conflicts = results
        .where(
          (result) => result.status == HealthImportReviewStatus.dayConflict,
        )
        .toList();
    for (final conflict in conflicts) {
      if (!mounted) return;
      final replace = await showGainerStackedDialog<bool>(
        context: context,
        title: 'Check-in an diesem Tag vorhanden',
        message:
            'Für ${HealthReviewCoordinator.localDateForSample(conflict.sample)} gibt es bereits einen Check-in. Soll nur das Gewicht durch ${conflict.sample.weightKilograms.toStringAsFixed(2)} kg ersetzt werden? Andere Check-in-Werte bleiben erhalten.',
        actions: const [
          GainerDialogAction(label: 'Überspringen', value: false),
          GainerDialogAction(
            label: 'Gewicht ersetzen',
            value: true,
            destructive: true,
          ),
        ],
      );
      if (!mounted) return;
      await widget.viewModel.confirmImport(
        replaceExistingFor: replace == true ? {conflict.sample.uuid} : const {},
        skipFor: replace == true ? const {} : {conflict.sample.uuid},
      );
    }
  }

  Future<void> _export(CompletedWorkoutCandidate workout) async {
    final confirmed = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Workout nach Apple Health exportieren?',
      message: 'Beginn, Ende und Trainingsart werden geschrieben. Der Export ist optional und wiederholbar, falls die Bestätigung verloren geht.',
      actions: const [
        GainerDialogAction(label: 'Abbrechen', value: false),
        GainerDialogAction(label: 'Export bestätigen', value: true),
      ],
    );
    if (confirmed != true || !mounted) return;
    final receipt = await widget.viewModel.exportWorkout(
      workout.id,
      confirmed: true,
    );
    if (!mounted || receipt == null) return;
    await showGainerStackedDialog<bool>(
      context: context,
      title: 'Apple Health',
      message: receipt.status == HealthExportStatus.saved
          ? 'Workout in Apple Health gespeichert.'
          : 'Workout war bereits in Apple Health vorhanden.',
      actions: const [GainerDialogAction(label: 'Fertig', value: true)],
    );
  }
}

Widget _field(
  BuildContext context,
  TextEditingController controller,
  String label,
) {
  final colors = GainerDesign.colorsOf(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      GainerSpacing.xs,
      GainerSpacing.m,
      GainerSpacing.xs,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: 5),
        CupertinoTextField(
          controller: controller,
          style: GainerTypography.body.copyWith(color: colors.primaryText),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: colors.elevatedSurface,
            borderRadius: BorderRadius.circular(GainerRadii.field),
          ),
        ),
      ],
    ),
  );
}

Widget _notice(BuildContext context, String text, {bool isError = false}) {
  final colors = GainerDesign.colorsOf(context);
  final tint = isError ? colors.destructive : colors.accent;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(GainerSpacing.s),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(GainerRadii.field),
    ),
    child: Text(
      text,
      style: GainerTypography.body.copyWith(
        color: isError ? colors.destructive : colors.primaryText,
      ),
    ),
  );
}

Widget _dataCard(BuildContext context, String title, String detail) {
  final colors = GainerDesign.colorsOf(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      10,
      GainerSpacing.m,
      10,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GainerTypography.body.copyWith(color: colors.primaryText),
        ),
        if (detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              detail,
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _switchRow(
  BuildContext context, {
  required String title,
  String? detail,
  required bool value,
  bool enabled = true,
  required ValueChanged<bool> onChanged,
}) {
  final colors = GainerDesign.colorsOf(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      10,
      GainerSpacing.xs,
      10,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                ),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    style: GainerTypography.label.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
        ),
        CupertinoSwitch(value: value, onChanged: enabled ? onChanged : null),
      ],
    ),
  );
}

Widget _actionCard(
  BuildContext context, {
  required String title,
  required String detail,
  required String actionLabel,
  required IconData icon,
  required VoidCallback? onPressed,
}) {
  final colors = GainerDesign.colorsOf(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      10,
      GainerSpacing.xs,
      10,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GainerTypography.body.copyWith(
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: GainerTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.all(8),
          onPressed: onPressed,
          child: Semantics(
            label: actionLabel,
            button: true,
            child: Icon(icon, color: colors.accent),
          ),
        ),
      ],
    ),
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _localTime(DateTime value) {
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _status(HealthImportReviewStatus status) => switch (status) {
  HealthImportReviewStatus.imported => 'In Gainer übernommen',
  HealthImportReviewStatus.duplicate => 'Bereits übernommen',
  HealthImportReviewStatus.dayConflict => 'Entscheidung erforderlich',
  HealthImportReviewStatus.skipped => 'Übersprungen',
};
