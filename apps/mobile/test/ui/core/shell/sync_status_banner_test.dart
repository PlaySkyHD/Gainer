import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_status.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/shell/sync_now_section.dart';
import 'package:gainer_mobile/ui/core/shell/sync_status_banner.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

import '../../../../integration_test/ui_design_fixture.dart'
    show createUiDesignFixture;
import '../components/component_harness.dart';

SyncRunReport _report(SyncRunState state) => SyncRunState.values.contains(state)
    ? SyncRunReport(state: state, pushed: 0, pulledBatches: 0)
    : throw StateError('unreachable');

void main() {
  late ValueNotifier<SyncStatus> status;
  late List<bool> calls;
  late Object? failure;

  Future<SyncRunReport> fake({bool takeOverWriting = false}) async {
    calls.add(takeOverWriting);
    if (failure case final error?) throw error;
    // Wie im echten Ablauf: nach der Übernahme meldet der Sync „Schreibgerät“.
    status.value = status.value.copyWith(isWriter: true);
    return _report(SyncRunState.synced);
  }

  setUp(() {
    status = ValueNotifier(const SyncStatus(isWriter: false));
    calls = [];
    failure = null;
  });

  tearDown(() => status.dispose());

  Widget banner() => componentHarness(
    child: SyncStatusBanner(
      status: status,
      synchronize: fake,
      child: const Center(child: Text('Inhalt')),
    ),
  );

  testWidgets('Schreibgerät: kein Hinweis, Inhalt bleibt sichtbar', (
    tester,
  ) async {
    status.value = const SyncStatus();
    await tester.pumpWidget(banner());

    expect(find.text('Dieses iPhone lädt nichts hoch'), findsNothing);
    expect(find.text('Inhalt'), findsOneWidget);
  });

  testWidgets('kein Schreibgerät: Hinweis mit Übernehmen über dem Inhalt', (
    tester,
  ) async {
    await tester.pumpWidget(banner());

    expect(find.text('Dieses iPhone lädt nichts hoch'), findsOneWidget);
    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.text('Inhalt'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Dieses iPhone lädt nichts hoch')).dy,
      lessThan(tester.getTopLeft(find.text('Inhalt')).dy),
    );
  });

  testWidgets('Übernehmen fragt nach und blendet den Hinweis danach aus', (
    tester,
  ) async {
    await tester.pumpWidget(banner());

    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Schreiben übernehmen?'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Übernehmen').last);
    await tester.pumpAndSettle();

    expect(calls, [true]);
    expect(find.text('Dieses iPhone lädt nichts hoch'), findsNothing);
  });

  testWidgets('Abbrechen übernimmt nicht und lässt den Hinweis stehen', (
    tester,
  ) async {
    await tester.pumpWidget(banner());

    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.text('Dieses iPhone lädt nichts hoch'), findsOneWidget);
  });

  testWidgets('verlangte Übergabe wird erklärt, der Hinweis bleibt', (
    tester,
  ) async {
    failure = const ApiException(
      statusCode: 409,
      code: 'handover_required',
      message: 'handover required',
    );
    await tester.pumpWidget(banner());

    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen').last);
    await tester.pumpAndSettle();

    expect(find.text('Übernehmen nicht möglich'), findsOneWidget);
    expect(find.textContaining('Dieses Gerät ablösen'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Dieses iPhone lädt nichts hoch'), findsOneWidget);
  });

  testWidgets('Tabs behalten ihren Zustand, wenn der Hinweis erscheint', (
    tester,
  ) async {
    status.value = const SyncStatus();
    final counter = ValueNotifier(0);
    addTearDown(counter.dispose);
    await tester.pumpWidget(
      componentHarness(
        child: SyncStatusBanner(
          status: status,
          synchronize: fake,
          child: _StatefulChild(counter),
        ),
      ),
    );
    await tester.tap(find.text('zählen'));
    await tester.pump();
    expect(find.text('Zähler 1'), findsOneWidget);

    status.value = const SyncStatus(isWriter: false);
    await tester.pump();

    expect(find.text('Zähler 1'), findsOneWidget);
  });

  group('Mehr: Fußnote', () {
    final now = DateTime.utc(2026, 10, 18, 12);

    test('relative deutsche Zeit', () {
      expect(
        relativeSyncTime(now.subtract(const Duration(seconds: 20)), now),
        'gerade eben',
      );
      expect(
        relativeSyncTime(now.subtract(const Duration(minutes: 2)), now),
        'vor 2 Min.',
      );
      expect(
        relativeSyncTime(now.subtract(const Duration(minutes: 59)), now),
        'vor 59 Min.',
      );
      expect(
        relativeSyncTime(now.subtract(const Duration(hours: 3)), now),
        'vor 3 Std.',
      );
      expect(
        relativeSyncTime(now.subtract(const Duration(hours: 23)), now),
        'vor 23 Std.',
      );
      expect(
        relativeSyncTime(DateTime.utc(2026, 10, 12, 10), now),
        'am 12.10.2026',
      );
    });

    test('Zeile mit Zeit und Anzahl, auch ohne bisherigen Sync', () {
      expect(
        syncStatusLine(
          SyncStatus(
            lastSyncedAtUtc: now.subtract(const Duration(minutes: 2)),
            pendingCount: 3,
          ),
          now,
        ),
        'Zuletzt synchronisiert vor 2 Min. · 3 ausstehend',
      );
      expect(
        syncStatusLine(const SyncStatus(), now),
        'Noch nicht synchronisiert · 0 ausstehend',
      );
    });

    testWidgets('steht unter Synchronisierung und folgt dem Zustand', (
      tester,
    ) async {
      status.value = SyncStatus(
        lastSyncedAtUtc: now.subtract(const Duration(minutes: 2)),
        pendingCount: 3,
      );
      await tester.pumpWidget(
        componentHarness(
          child: SyncNowSection(
            online: true,
            synchronize: fake,
            status: status,
            clock: () => now,
          ),
        ),
      );
      expect(
        find.text('Zuletzt synchronisiert vor 2 Min. · 3 ausstehend'),
        findsOneWidget,
      );

      status.value = status.value.copyWith(pendingCount: 0);
      await tester.pump();

      expect(
        find.text('Zuletzt synchronisiert vor 2 Min. · 0 ausstehend'),
        findsOneWidget,
      );
    });
  });

  group('in der Shell', () {
    testWidgets('Hinweis in allen Tabs, Fußnote unter Mehr', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await tester.runAsync(createUiDesignFixture);
      addTearDown(() => tester.runAsync(fixture!.dispose));
      await tester.pumpWidget(
        fixture!.app(GainerTheme.forBrightness(Brightness.light)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final notifier = fixture.account.syncStatus as ValueNotifier<SyncStatus>;
      expect(notifier.value.isWriter, isTrue);
      expect(find.text('Dieses iPhone lädt nichts hoch'), findsNothing);

      notifier.value = SyncStatus(
        lastSyncedAtUtc: DateTime.now().subtract(
          const Duration(minutes: 2, seconds: 30),
        ),
        pendingCount: 3,
        isWriter: false,
      );
      for (final area in MobileArea.values) {
        await tester.tap(find.text(area.label).last);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text('Dieses iPhone lädt nichts hoch'),
          findsOneWidget,
          reason: area.label,
        );
      }
      expect(
        find.text('Zuletzt synchronisiert vor 2 Min. · 3 ausstehend'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lokale Änderungen erhöhen die Zahl ausstehender Einträge', (
      tester,
    ) async {
      final fixture = await tester.runAsync(createUiDesignFixture);
      addTearDown(() => tester.runAsync(fixture!.dispose));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final before = fixture!.account.syncStatus.value.pendingCount;

      await tester.runAsync(() async {
        await fixture.account.training.startEmpty(title: 'Neu');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });

      expect(fixture.account.syncStatus.value.pendingCount, before + 1);
    });
  });
}

class _StatefulChild extends StatefulWidget {
  const _StatefulChild(this.counter);

  final ValueNotifier<int> counter;

  @override
  State<_StatefulChild> createState() => _StatefulChildState();
}

class _StatefulChildState extends State<_StatefulChild> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('Zähler $_count'),
      CupertinoButton(
        onPressed: () => setState(() => _count++),
        child: const Text('zählen'),
      ),
    ],
  );
}
