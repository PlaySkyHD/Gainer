import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/shell/sync_now_section.dart';

import '../components/component_harness.dart';

SyncRunReport _report(SyncRunState state) =>
    SyncRunReport(state: state, pushed: 0, pulledBatches: 0);

void main() {
  late List<bool> calls;
  late List<Object> results;

  Future<SyncRunReport> fake({bool takeOverWriting = false}) async {
    calls.add(takeOverWriting);
    final next = results.removeAt(0);
    if (next is Exception) throw next;
    return next as SyncRunReport;
  }

  setUp(() {
    calls = [];
    results = [];
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    componentHarness(
      child: SingleChildScrollView(
        child: SyncNowSection(online: true, synchronize: fake),
      ),
    ),
  );

  testWidgets('anderes Schreibgerät: Übernahme nach Bestätigung', (
    tester,
  ) async {
    results = [
      _report(SyncRunState.inactiveClient),
      _report(SyncRunState.synced),
    ];
    await pump(tester);
    expect(find.byKey(const ValueKey('sync-take-over')), findsNothing);

    await tester.tap(find.text('Jetzt synchronisieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('anderes Gerät'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-take-over')));
    await tester.pumpAndSettle();
    expect(find.text('Schreiben übernehmen?'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    expect(calls, [false, true]);
    expect(find.textContaining('jetzt dein Schreibgerät'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-take-over')), findsNothing);
  });

  testWidgets('Abbrechen übernimmt nicht', (tester) async {
    results = [_report(SyncRunState.inactiveClient)];
    await pump(tester);
    await tester.tap(find.text('Jetzt synchronisieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sync-take-over')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(calls, [false]);
  });

  testWidgets('verlangte Übergabe wird erklärt', (tester) async {
    results = [
      _report(SyncRunState.inactiveClient),
      const ApiException(
        statusCode: 409,
        code: 'handover_required',
        message: 'handover required',
      ),
    ];
    await pump(tester);
    await tester.tap(find.text('Jetzt synchronisieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sync-take-over')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dieses Gerät ablösen'), findsOneWidget);
  });

  testWidgets('weitere Zustände und Fehler', (tester) async {
    results = [
      _report(SyncRunState.idle),
      const ApiException(
        statusCode: 409,
        code: 'handover_in_progress',
        message: 'in progress',
      ),
      Exception('offline'),
    ];
    await pump(tester);
    await tester.tap(find.text('Jetzt synchronisieren'));
    await tester.pumpAndSettle();
    expect(find.text('Keine ausstehenden Änderungen.'), findsOneWidget);
    await tester.tap(find.text('Jetzt synchronisieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Geräteübergabe'), findsOneWidget);
    await tester.tap(find.text('Jetzt synchronisieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nicht möglich'), findsOneWidget);
  });
}
