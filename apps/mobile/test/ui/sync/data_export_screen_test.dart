import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/data_export_service.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_status.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/features/sync/data_export_screen.dart';

import '../cardio/cardio_test_support.dart';
import '../training/training_test_support.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeDataExportService service, {
    bool online = true,
    int pending = 0,
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        brightness: brightness,
        home: DataExportScreen(
          service: service,
          online: online,
          status: ValueNotifier(SyncStatus(pendingCount: pending)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder start() => find.byKey(const ValueKey('data-export-start'));

  testWidgets('erstellt den Export und zeigt währenddessen einen Ladekreis', (
    tester,
  ) async {
    final service = FakeDataExportService();
    await open(tester, service);
    expect(find.textContaining('Passkeys, Geräte'), findsOneWidget);

    await tester.tap(start());
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await tester.tap(start());
    expect(service.exports, 1);

    service.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byKey(const ValueKey('data-export-error')), findsNothing);
  });

  testWidgets(
    'ohne Verbindung ist der Export gesperrt und der Grund steht da',
    (tester) async {
      final service = FakeDataExportService();
      await open(tester, service, online: false);

      expect(find.textContaining('nur mit Verbindung'), findsOneWidget);
      await tester.tap(start());
      await tester.pumpAndSettle();
      expect(service.exports, 0);
    },
  );

  testWidgets('weist auf noch nicht gesendete Änderungen hin', (tester) async {
    await open(tester, FakeDataExportService(), pending: 3);
    expect(
      find.textContaining('3 Änderungen sind noch nicht gesendet und fehlen'),
      findsOneWidget,
    );

    await open(tester, FakeDataExportService(), pending: 1);
    expect(
      find.textContaining('1 Änderung ist noch nicht gesendet und fehlt'),
      findsOneWidget,
    );
  });

  testWidgets('meldet das Limit und andere Fehler verständlich', (
    tester,
  ) async {
    final limited = FakeDataExportService(
      error: const ApiException(
        statusCode: 429,
        code: 'http_429',
        message: 'Too many requests.',
      ),
    );
    await open(tester, limited);
    await tester.tap(start());
    await tester.pumpAndSettle();
    expect(find.textContaining('Viertelstunde'), findsOneWidget);

    final broken = FakeDataExportService(error: StateError('kaputt'));
    await open(tester, broken);
    await tester.tap(start());
    await tester.pumpAndSettle();
    expect(find.textContaining('nicht geklappt'), findsOneWidget);
    expect(find.textContaining('kaputt'), findsNothing);
  });

  testWidgets('läuft bei Textgröße 2 nicht über', (tester) async {
    await open(tester, FakeDataExportService(), pending: 2, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'data export screen matches golden in ${brightness.name} mode',
      (tester) async {
        await open(
          tester,
          FakeDataExportService(),
          pending: 2,
          brightness: brightness,
        );
        await expectLater(
          find.byType(DataExportScreen),
          matchesGoldenFile(
            'goldens/data_export_screen_${brightness.name}.png',
          ),
        );
      },
      tags: ['golden'],
    );
  }
}

class FakeDataExportService implements DataExportService {
  FakeDataExportService({this.error});

  final Object? error;
  int exports = 0;
  Completer<void>? _pending;

  @override
  Future<void> exportAndShare() {
    exports++;
    if (error case final error?) return Future.error(error);
    return (_pending = Completer<void>()).future;
  }

  void complete() => _pending?.complete();
}
