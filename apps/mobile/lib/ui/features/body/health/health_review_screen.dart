import 'package:flutter/material.dart';

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
    final start = today.subtract(const Duration(days: 6));
    _from = TextEditingController(text: _date(start));
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
      return Scaffold(
        appBar: AppBar(title: const Text('Apple Health')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Health-Daten werden nur nach deiner Aktion geprüft. Leere Ergebnisse sagen nicht aus, ob der Zugriff verweigert wurde.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Gewicht übernehmen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _from,
                      decoration: const InputDecoration(
                        labelText: 'Von (JJJJ-MM-TT)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _to,
                      decoration: const InputDecoration(
                        labelText: 'Bis (JJJJ-MM-TT)',
                      ),
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: vm.isLoading
                    ? null
                    : () => vm.prepareReview(
                        fromLocalDate: _from.text,
                        toLocalDate: _to.text,
                      ),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Health-Proben laden'),
              ),
              if (review != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Prüfe Gewicht, Messzeit und Quelle. Erst bestätigte Einträge werden an den Gainer-Sync vorgemerkt.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (review.samples.isEmpty)
                  const ListTile(
                    title: Text('Keine Werte im Zeitraum gefunden.'),
                    subtitle: Text(
                      'Das bedeutet nicht automatisch, dass der Zugriff verweigert wurde.',
                    ),
                  ),
                for (final sample in review.samples)
                  CheckboxListTile(
                    value: vm.selectedProbeIds.contains(sample.uuid),
                    onChanged: (value) =>
                        vm.selectSample(sample.uuid, value ?? false),
                    title: Text(
                      '${sample.weightKilograms.toStringAsFixed(2)} kg',
                    ),
                    subtitle: Text(
                      '${_localTime(sample.measuredAtUtc)} · ${sample.sourceName}',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                CheckboxListTile(
                  value: vm.serverSyncNoticeAccepted,
                  onChanged: vm.selectedProbeIds.isEmpty
                      ? null
                      : (value) => vm.acceptServerSyncNotice(value ?? false),
                  title: const Text(
                    'Ich bestätige, dass ausgewählte Check-ins zu meinem Gainer-Konto synchronisiert werden können.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: vm.cancelReview,
                      child: const Text('Prüfung abbrechen'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed:
                          vm.isLoading ||
                              !vm.serverSyncNoticeAccepted ||
                              vm.selectedProbeIds.isEmpty
                          ? null
                          : _confirmImport,
                      child: const Text('Auswahl übernehmen'),
                    ),
                  ],
                ),
              ],
              if (vm.lastResults.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Importstatus',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final result in vm.lastResults)
                  ListTile(
                    title: Text(_status(result.status)),
                    subtitle: Text(
                      '${result.sample.weightKilograms.toStringAsFixed(2)} kg · ${_localTime(result.sample.measuredAtUtc)}',
                    ),
                  ),
              ],
              if (vm.errorMessage != null)
                Semantics(
                  liveRegion: true,
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(vm.errorMessage!),
                    ),
                  ),
                ),
              const Divider(height: 32),
              Text(
                'Abgeschlossene Workouts exportieren',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Nur serverbestätigte eigene Workouts werden angeboten. Es werden keine geschätzten Kalorien oder Pulswerte ergänzt.',
              ),
              if (vm.completedWorkouts.isEmpty)
                const ListTile(
                  title: Text(
                    'Keine serverbestätigten abgeschlossenen Workouts verfügbar.',
                  ),
                ),
              for (final workout in vm.completedWorkouts)
                ListTile(
                  title: Text(workout.value.templateNameSnapshot),
                  subtitle: Text(
                    '${_localTime(DateTime.parse(workout.value.startedAtUtc))} · ${_localTime(DateTime.parse(workout.value.completedAtUtc!))}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Workout nach Apple Health exportieren',
                    icon: const Icon(Icons.upload),
                    onPressed: vm.isLoading ? null : () => _export(workout),
                  ),
                ),
              if (vm.isLoading) const LinearProgressIndicator(),
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
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Check-in an diesem Tag vorhanden'),
          content: Text(
            'Für ${HealthReviewCoordinator.localDateForSample(conflict.sample)} gibt es bereits einen Check-in. Soll nur das Gewicht durch ${conflict.sample.weightKilograms.toStringAsFixed(2)} kg ersetzt werden? Andere Check-in-Werte bleiben erhalten.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Überspringen'),
            ),
            FilledButton(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout nach Apple Health exportieren?'),
        content: const Text(
          'Beginn, Ende und Trainingsart werden geschrieben. Der Export ist optional und wiederholbar, falls die Bestätigung verloren geht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
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
    if (mounted && receipt != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            receipt.status == HealthExportStatus.saved
                ? 'Workout in Apple Health gespeichert.'
                : 'Workout war bereits in Apple Health vorhanden.',
          ),
        ),
      );
    }
  }
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
