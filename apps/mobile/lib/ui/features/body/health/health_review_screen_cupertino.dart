import 'package:flutter/cupertino.dart';

import '../../../../data/repositories/health/health_review_coordinator.dart';
import '../../../../data/services/platform/platform_ports.dart';
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
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Apple Health'),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _notice(
                context,
                'Health-Daten werden nur nach deiner Aktion geprüft. Leere Ergebnisse sagen nicht aus, ob der Zugriff verweigert wurde.',
              ),
              _heading(context, 'Gewicht übernehmen'),
              _field(context, _from, 'Von (JJJJ-MM-TT)'),
              _field(context, _to, 'Bis (JJJJ-MM-TT)'),
              CupertinoButton.filled(
                onPressed: vm.isLoading
                    ? null
                    : () => vm.prepareReview(
                        fromLocalDate: _from.text,
                        toLocalDate: _to.text,
                      ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.heart),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Health-Proben laden',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              if (review != null) ...[
                _notice(
                  context,
                  'Prüfe Gewicht, Messzeit und Quelle. Erst bestätigte Einträge werden an den Gainer-Sync vorgemerkt.',
                ),
                if (review.samples.isEmpty)
                  _dataCard(
                    context,
                    'Keine Werte im Zeitraum gefunden.',
                    'Das bedeutet nicht automatisch, dass der Zugriff verweigert wurde.',
                  ),
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
                Row(
                  children: [
                    CupertinoButton(
                      onPressed: vm.cancelReview,
                      child: const Text('Prüfung abbrechen'),
                    ),
                    const Spacer(),
                    Flexible(
                      child: CupertinoButton.filled(
                        onPressed:
                            vm.isLoading ||
                                !vm.serverSyncNoticeAccepted ||
                                vm.selectedProbeIds.isEmpty
                            ? null
                            : _confirmImport,
                        child: const Text(
                          'Auswahl übernehmen',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (vm.lastResults.isNotEmpty) ...[
                _heading(context, 'Importstatus'),
                for (final result in vm.lastResults)
                  _dataCard(
                    context,
                    _status(result.status),
                    '${result.sample.weightKilograms.toStringAsFixed(2)} kg · ${_localTime(result.sample.measuredAtUtc)}',
                  ),
              ],
              if (vm.errorMessage != null)
                _notice(context, vm.errorMessage!, isError: true),
              _heading(context, 'Abgeschlossene Workouts exportieren'),
              const Text(
                'Nur serverbestätigte eigene Workouts werden angeboten. Es werden keine geschätzten Kalorien oder Pulswerte ergänzt.',
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
                  title: workout.value.templateNameSnapshot,
                  detail:
                      '${_localTime(DateTime.parse(workout.value.startedAtUtc))} · ${_localTime(DateTime.parse(workout.value.completedAtUtc!))}',
                  actionLabel: 'Workout nach Apple Health exportieren',
                  icon: CupertinoIcons.arrow_up_doc,
                  onPressed: vm.isLoading ? null : () => _export(workout),
                ),
              if (vm.isLoading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
            ],
          ),
        ),
      );
    },
  );

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
      final replace = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Check-in an diesem Tag vorhanden'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Für ${HealthReviewCoordinator.localDateForSample(conflict.sample)} gibt es bereits einen Check-in. Soll nur das Gewicht durch ${conflict.sample.weightKilograms.toStringAsFixed(2)} kg ersetzt werden? Andere Check-in-Werte bleiben erhalten.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Überspringen'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gewicht ersetzen'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await widget.viewModel.confirmImport(
        replaceExistingFor: replace == true ? {conflict.sample.uuid} : const {},
        skipFor: replace == true ? const {} : {conflict.sample.uuid},
      );
    }
  }

  Future<void> _export(CompletedWorkoutCandidate workout) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Workout nach Apple Health exportieren?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Beginn, Ende und Trainingsart werden geschrieben. Der Export ist optional und wiederholbar, falls die Bestätigung verloren geht.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export bestätigen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final receipt = await widget.viewModel.exportWorkout(
      workout.id,
      confirmed: true,
    );
    if (!mounted || receipt == null) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Apple Health'),
        content: Text(
          receipt.status == HealthExportStatus.saved
              ? 'Workout in Apple Health gespeichert.'
              : 'Workout war bereits in Apple Health vorhanden.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  }
}

Widget _heading(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
  child: Text(
    title,
    style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
  ),
);

Widget _field(
  BuildContext context,
  TextEditingController controller,
  String label,
) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 5),
      CupertinoTextField(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ],
  ),
);

Widget _notice(
  BuildContext context,
  String text, {
  bool isError = false,
}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 6),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: (isError ? CupertinoColors.systemRed : CupertinoColors.systemBlue)
        .resolveFrom(context)
        .withValues(alpha: .12),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    text,
    style: TextStyle(
      color: isError ? CupertinoColors.systemRed.resolveFrom(context) : null,
    ),
  ),
);

Widget _dataCard(BuildContext context, String title, String detail) =>
    Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
        ],
      ),
    );

Widget _switchRow(
  BuildContext context, {
  required String title,
  String? detail,
  required bool value,
  bool enabled = true,
  required ValueChanged<bool> onChanged,
}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 4),
  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
  decoration: BoxDecoration(
    color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  detail,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
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

Widget _actionCard(
  BuildContext context, {
  required String title,
  required String detail,
  required String actionLabel,
  required IconData icon,
  required VoidCallback? onPressed,
}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 4),
  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
  decoration: BoxDecoration(
    color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 3),
            Text(
              detail,
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        onPressed: onPressed,
        child: Semantics(label: actionLabel, button: true, child: Icon(icon)),
      ),
    ],
  ),
);

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
