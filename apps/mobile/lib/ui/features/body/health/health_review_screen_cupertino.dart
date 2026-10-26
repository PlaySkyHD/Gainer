import 'package:flutter/cupertino.dart';

import '../../../../data/repositories/health/health_review_coordinator.dart';
import '../../../../data/services/platform/platform_ports.dart';
import '../../../../domain/models/training/training_schedule.dart';
import '../../../core/components/components.dart';
import '../../../core/german_date_time.dart';
import '../../../core/theme.dart';
import 'health_review_view_model.dart';

class HealthReviewScreen extends StatefulWidget {
  const HealthReviewScreen({super.key, required this.viewModel, this.clock});
  final HealthReviewViewModel viewModel;

  /// Uhr für „heute“; Tests setzen einen festen Tag. Standard: [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<HealthReviewScreen> createState() => _HealthReviewScreenState();
}

class _HealthReviewScreenState extends State<HealthReviewScreen> {
  late DateTime _from;
  late DateTime _to;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final today = _now();
    // Kalendertage statt 6 × 24 Stunden, sonst verrutscht der Start über eine
    // Zeitumstellung kurz nach Mitternacht um einen Tag.
    _from = LocalDay.of(today).addDays(-6).toDateTime();
    _to = today;
    widget.viewModel.load();
  }

  void _prepare(HealthReviewViewModel vm) =>
      vm.prepareReview(fromLocalDate: _date(_from), toLocalDate: _date(_to));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final review = vm.review;
      return GainerScaffold(
        title: 'Apple Health',
        trailing: [
          if (review != null) ...[
            GainerToolbarButton(
              icon: CupertinoIcons.arrow_clockwise,
              semanticLabel: 'Health-Proben neu laden',
              onPressed: vm.isLoading ? null : () => _prepare(vm),
            ),
            GainerToolbarButton(
              icon: CupertinoIcons.xmark,
              semanticLabel: 'Prüfung abbrechen',
              onPressed: vm.cancelReview,
            ),
          ],
        ],
        children: [
          GainerGroupedSection(
            header: 'Gewicht übernehmen',
            footer: 'Health-Daten werden nur nach deiner Aktion geprüft. Leere Ergebnisse sagen nicht aus, ob der Zugriff verweigert wurde.',
            children: [
              GainerDateRow(
                key: const ValueKey('health-from'),
                title: 'Von',
                value: _from,
                format: _displayDate,
                maximum: _to,
                onChanged: vm.isLoading
                    ? null
                    : (picked) => setState(() => _from = picked),
              ),
              GainerDateRow(
                key: const ValueKey('health-to'),
                title: 'Bis',
                value: _to,
                format: _displayDate,
                minimum: _from,
                maximum: _now(),
                onChanged: vm.isLoading
                    ? null
                    : (picked) => setState(() => _to = picked),
              ),
            ],
          ),
          if (review == null) ...[
            const SizedBox(height: GainerSpacing.m),
            GainerPillButton(
              label: 'Health-Proben laden',
              expand: true,
              onPressed: vm.isLoading ? null : () => _prepare(vm),
            ),
          ],
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
    const SizedBox(height: GainerSpacing.m),
    GainerGroupedSection(
      header: 'Gefundene Werte',
      footer: 'Prüfe Gewicht, Messzeit und Quelle. Erst bestätigte Einträge werden an den Gainer-Sync vorgemerkt.',
      children: [
        if (review.samples.isEmpty)
          _dataRow(
            context,
            'Keine Werte im Zeitraum gefunden.',
            'Das bedeutet nicht automatisch, dass der Zugriff verweigert wurde.',
          ),
        for (final sample in review.samples)
          GainerListRow(
            title: '${sample.weightKilograms.toStringAsFixed(2)} kg',
            subtitle:
                '${_localTime(sample.measuredAtUtc)} · ${sample.sourceName}',
            trailing: CupertinoSwitch(
              value: vm.selectedProbeIds.contains(sample.uuid),
              onChanged: (value) => vm.selectSample(sample.uuid, value),
            ),
          ),
        GainerListRow(
          title: 'Ich bestätige, dass ausgewählte Check-ins zu meinem Gainer-Konto synchronisiert werden können.',
          trailing: CupertinoSwitch(
            value: vm.serverSyncNoticeAccepted,
            onChanged: vm.selectedProbeIds.isEmpty
                ? null
                : vm.acceptServerSyncNotice,
          ),
        ),
      ],
    ),
    const SizedBox(height: GainerSpacing.m),
    GainerPillButton(
      label: 'Auswahl übernehmen',
      expand: true,
      onPressed:
          vm.isLoading ||
              !vm.serverSyncNoticeAccepted ||
              vm.selectedProbeIds.isEmpty
          ? null
          : _confirmImport,
    ),
  ];

  List<Widget> _importStatusChildren(
    BuildContext context,
    HealthReviewViewModel vm,
  ) => [
    const SizedBox(height: GainerSpacing.m),
    GainerGroupedSection(
      header: 'Importstatus',
      children: [
        for (final result in vm.lastResults)
          _dataRow(
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
    const SizedBox(height: GainerSpacing.m),
    GainerGroupedSection(
      header: 'Abgeschlossene Workouts exportieren',
      footer: 'Nur serverbestätigte eigene Workouts werden angeboten. Es werden keine geschätzten Kalorien oder Pulswerte ergänzt.',
      children: [
        if (vm.completedWorkouts.isEmpty)
          _dataRow(
            context,
            'Keine serverbestätigten abgeschlossenen Workouts verfügbar.',
            '',
          ),
        for (final workout in vm.completedWorkouts)
          Semantics(
            hint: 'Workout nach Apple Health exportieren',
            child: GainerListRow(
              title: workout.value.title,
              subtitle:
                  '${_localTime(workout.value.startedAtUtc)} · ${_localTime(workout.value.endedAtUtc!)}',
              leadingIcon: CupertinoIcons.arrow_up_doc,
              showChevron: true,
              onTap: vm.isLoading ? null : () => _export(workout),
            ),
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

/// Textzeile in einer Gruppe: Titel, optional Detail in Sekundärtext.
Widget _dataRow(BuildContext context, String title, String detail) {
  final colors = GainerDesign.colorsOf(context);
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: GainerSpacing.m,
      vertical: 11,
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

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _displayDate(DateTime value) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year}';
}

String _localTime(DateTime value) => formatGermanDateTime(value);

String _status(HealthImportReviewStatus status) => switch (status) {
  HealthImportReviewStatus.imported => 'In Gainer übernommen',
  HealthImportReviewStatus.duplicate => 'Bereits übernommen',
  HealthImportReviewStatus.dayConflict => 'Entscheidung erforderlich',
  HealthImportReviewStatus.skipped => 'Übersprungen',
};
