import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/coach/coach_memory_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

/// Gedächtnis im Speicher; [failWith] lässt die nächste Änderung scheitern.
class FakeCoachMemoryRepository implements CoachMemoryRepository {
  FakeCoachMemoryRepository([List<ApiCoachMemory>? items])
    : items = [...?items];

  final List<ApiCoachMemory> items;
  final calls = <String>[];
  int maxEntries = 50;
  Object? failWith;
  Object? failListWith;

  /// Hält `create` an, bis der Completer erfüllt ist.
  Completer<void>? createGate;

  /// Hält `update` an, bis der Completer erfüllt ist.
  Completer<void>? updateGate;

  /// Je `list`-Aufruf ein Completer: Der Aufruf liest den Stand sofort und
  /// antwortet erst, wenn sein Completer erfüllt ist (veraltete Antwort).
  final listGates = <Completer<void>>[];

  /// Wie der Server: Ein schon gemerkter Text liefert den vorhandenen Eintrag
  /// mit neuer Kategorie, statt einen neuen anzulegen.
  bool createReturnsExisting = false;
  var _next = 0;

  @override
  Future<ApiCoachMemoryList> list() async {
    calls.add('list');
    if (failListWith case final error?) {
      failListWith = null;
      throw error;
    }
    final snapshot = ApiCoachMemoryList(
      items: [...items],
      maxEntries: maxEntries,
    );
    if (listGates.isNotEmpty) await listGates.removeAt(0).future;
    return snapshot;
  }

  @override
  Future<ApiCoachMemory> create(
    CoachMemoryCategory category,
    String text,
  ) async {
    calls.add('create ${category.wireName} $text');
    await createGate?.future;
    _throwIfScripted();
    final existing = items.indexWhere((item) => item.text == text);
    if (createReturnsExisting && existing >= 0) {
      final current = items[existing];
      return items[existing] = memoryItem(
        current.id,
        category,
        current.text,
        version: current.version + (current.category == category ? 0 : 1),
      );
    }
    final memory = memoryItem(
      'aaaaaaaa-0000-4000-8000-${(_next++).toString().padLeft(12, '0')}',
      category,
      text,
    );
    items.insert(0, memory);
    return memory;
  }

  /// Basisversionen der `update`-Aufrufe, in Reihenfolge.
  final baseVersions = <int?>[];

  @override
  Future<ApiCoachMemory> update(
    String id,
    CoachMemoryCategory category,
    String text, {
    int? baseVersion,
    String? unknownCategory,
  }) async {
    calls.add('update $id ${unknownCategory ?? category.wireName} $text');
    baseVersions.add(baseVersion);
    await updateGate?.future;
    _throwIfScripted();
    final index = items.indexWhere((item) => item.id == id);
    final updated = ApiCoachMemory(
      id: id,
      category: category,
      text: text,
      createdAtUtc: items[index].createdAtUtc,
      updatedAtUtc: items[index].updatedAtUtc,
      version: items[index].version + 1,
      unknownCategory: unknownCategory,
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete $id');
    _throwIfScripted();
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> deleteAll() async {
    calls.add('deleteAll');
    _throwIfScripted();
    items.clear();
  }

  void _throwIfScripted() {
    if (failWith case final error?) {
      failWith = null;
      throw error;
    }
  }
}

ApiCoachMemory memoryItem(
  String id,
  CoachMemoryCategory category,
  String text, {
  int version = 1,
}) => ApiCoachMemory(
  id: id,
  category: category,
  text: text,
  createdAtUtc: DateTime.utc(2026, 10, 24, 12),
  updatedAtUtc: DateTime.utc(2026, 10, 24, 12),
  version: version,
);

const networkError = ApiException(
  statusCode: null,
  code: 'network_error',
  message: 'offline',
);

const limitReached = ApiException(
  statusCode: 409,
  code: 'memory_limit_reached',
  message: 'full',
);

const memoryConflict = ApiException(
  statusCode: 409,
  code: 'memory_conflict',
  message: 'conflict',
);

const memoryNotFound = ApiException(
  statusCode: 404,
  code: 'memory_not_found',
  message: 'gone',
);

const serverError = ApiException(
  statusCode: 500,
  code: 'server_error',
  message: 'boom',
);

/// Beispielgedächtnis ohne echte Nutzerdaten.
List<ApiCoachMemory> sampleMemories() => [
  memoryItem(
    '11111111-0000-4000-8000-000000000001',
    CoachMemoryCategory.goal,
    'Halbmarathon im Mai',
  ),
  memoryItem(
    '11111111-0000-4000-8000-000000000002',
    CoachMemoryCategory.intolerance,
    'Laktoseintoleranz',
  ),
  memoryItem(
    '11111111-0000-4000-8000-000000000003',
    CoachMemoryCategory.preference,
    'Trainiert lieber morgens',
  ),
  memoryItem(
    '11111111-0000-4000-8000-000000000004',
    CoachMemoryCategory.injury,
    'Linke Schulter schonen',
  ),
];

/// Startet [home] in einer CupertinoApp mit Gainer-Theme und Textgröße.
Future<void> pumpCoachApp(
  WidgetTester tester,
  Widget home, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: GainerTheme.forBrightness(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}
