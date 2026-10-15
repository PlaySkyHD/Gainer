import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

import '../../../integration_test/ui_design_test.dart'
    show UiDesignFixture, createUiDesignFixture;

const _previewNames = [
  'tab-heute',
  'tab-checkin',
  'sheet-checkin',
  'sheet-goal',
  'date-picker',
  'tab-essen',
  'editor-essen',
  'tab-training',
  'editor-training',
  'tab-mehr',
  'tab-dark-heute',
  'tab-dark-checkin',
  'tab-dark-essen',
  'tab-dark-training',
  'tab-dark-mehr',
  'sheet-dark-checkin',
  'editor-dark-essen',
  'editor-dark-training',
  'exercise-progress',
  'exercise-dark-progress',
];

void main() {
  final fontPath = Platform.environment['GAINER_REVIEW_FONT'];
  testWidgets(
    'writes readable fixture-backed Windows font-substitution previews',
    (tester) async {
      await tester.runAsync(() => _loadCupertinoFonts(fontPath!));
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(786, 1704);
      tester.view.viewPadding = const FakeViewPadding(top: 118, bottom: 68);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewPadding);

      final fixture = await tester.runAsync(createUiDesignFixture);
      if (fixture == null) {
        throw StateError('Could not create preview fixture.');
      }
      final boundaryKey = GlobalKey();
      final output = Directory('../../artifacts/mobile/local-ui-preview');
      await tester.runAsync(() async {
        await output.create(recursive: true);
        for (final name in _previewNames) {
          final image = File(
            '${output.path}/$name-windows-font-substitution.png',
          );
          if (await image.exists()) {
            await image.delete();
          }
        }
      });

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: fixture.app(GainerTheme.light),
        ),
      );
      await tester.pumpAndSettle();
      await _waitForExerciseProgress(tester, fixture);
      await _savePreview(tester, boundaryKey, output, 'tab-heute');
      await _scrollProgressUntilVisible(
        tester,
        find.text('148 g Protein pro erfasstem Tag'),
      );
      expect(find.text('148 g Protein pro erfasstem Tag'), findsOneWidget);
      _resetProgressScroll(tester);
      await tester.pumpAndSettle();
      await _scrollProgressUntilVisible(tester, find.text('Übungsfortschritt'));
      await _savePreview(tester, boundaryKey, output, 'exercise-progress');

      await _tapTab(tester, 'Check-in');
      await _savePreview(tester, boundaryKey, output, 'tab-checkin');
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('body-open-checkin')),
      );
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();
      await _savePreview(tester, boundaryKey, output, 'sheet-checkin');
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('body-open-goal')),
      );
      await tester.tap(find.byKey(const ValueKey('body-open-goal')));
      await tester.pumpAndSettle();
      await _savePreview(tester, boundaryKey, output, 'sheet-goal');
      await tester.tap(find.byKey(const ValueKey('body-start-date')));
      await tester.pumpAndSettle();
      await _savePreview(tester, boundaryKey, output, 'date-picker');
      await tester.tap(find.byKey(const ValueKey('body-date-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      await _tapTab(tester, 'Essen');
      await _savePreview(tester, boundaryKey, output, 'tab-essen');
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('nutrition-add-food')),
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('nutrition-entry-name')),
      );
      await _savePreview(tester, boundaryKey, output, 'editor-essen');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await _tapTab(tester, 'Training');
      await _savePreview(tester, boundaryKey, output, 'tab-training');
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('training-create-template-route')),
      );
      await tester.tap(
        find.byKey(const ValueKey('training-create-template-route')),
      );
      await tester.pumpAndSettle();
      await _savePreview(tester, boundaryKey, output, 'editor-training');
      await tester.tap(find.byKey(const ValueKey('training-cancel-template')));
      await tester.pumpAndSettle();

      await _tapTab(tester, 'Mehr');
      await _savePreview(tester, boundaryKey, output, 'tab-mehr');

      await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: fixture.app(GainerTheme.dark)),
      );
      await tester.pumpAndSettle();
      for (final tab in const [
        ('Heute', 'tab-dark-heute'),
        ('Check-in', 'tab-dark-checkin'),
        ('Essen', 'tab-dark-essen'),
        ('Training', 'tab-dark-training'),
        ('Mehr', 'tab-dark-mehr'),
      ]) {
        await _tapTab(tester, tab.$1);
        _resetActiveListScroll(tester);
        await tester.pumpAndSettle();
        if (tab.$1 == 'Heute') {
          expect(
            find.text('Dein Fortschritt aus deinen Einträgen'),
            findsOneWidget,
          );
        }
        await _savePreview(tester, boundaryKey, output, tab.$2);
      }
      await _tapTab(tester, 'Heute');
      await _scrollProgressUntilVisible(tester, find.text('Übungsfortschritt'));
      await _savePreview(tester, boundaryKey, output, 'exercise-dark-progress');
      await _tapTab(tester, 'Check-in');
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('body-open-checkin')),
      );
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();
      await _savePreview(tester, boundaryKey, output, 'sheet-dark-checkin');
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      await _tapTab(tester, 'Essen');
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('nutrition-add-food')),
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('nutrition-entry-name')),
      );
      await _savePreview(tester, boundaryKey, output, 'editor-dark-essen');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await _tapTab(tester, 'Training');
      await _scrollActiveListUntilVisible(
        tester,
        find.byKey(const ValueKey('training-create-template-route')),
      );
      await tester.tap(
        find.byKey(const ValueKey('training-create-template-route')),
      );
      await tester.pumpAndSettle();
      await _savePreview(tester, boundaryKey, output, 'editor-dark-training');
      await tester.tap(find.byKey(const ValueKey('training-cancel-template')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        for (final name in _previewNames) {
          final path = '${output.path}/$name-windows-font-substitution.png';
          final bytes = await File(path).readAsBytes();
          if (!_isPng(bytes)) {
            throw StateError('Invalid local preview PNG: $name');
          }
          final header = ByteData.sublistView(bytes);
          final width = header.getUint32(16, Endian.big);
          final height = header.getUint32(20, Endian.big);
          if (width < 200 || width > 2000 || height < 400 || height > 4000) {
            throw StateError('Unexpected local preview dimensions: $name');
          }
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      var disposalComplete = false;
      Object? disposalError;
      final disposal = fixture.dispose().then<void>(
        (_) => disposalComplete = true,
        onError: (Object error, StackTrace _) {
          disposalError = error;
          disposalComplete = true;
        },
      );
      for (var attempt = 0; attempt < 100 && !disposalComplete; attempt++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(disposalComplete, isTrue, reason: 'Fixture disposal timed out.');
      await disposal;
      expect(disposalError, isNull);
    },
    skip: fontPath == null,
  );
}

Future<void> _loadCupertinoFonts(String path) async {
  final bytes = await File(path).readAsBytes();
  for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  final icons = await rootBundle.load(
    'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  );
  final iconLoader = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(Future.value(icons));
  await iconLoader.load();
}

bool _isPng(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24) {
    return false;
  }
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) {
      return false;
    }
  }
  return bytes[12] == 73 &&
      bytes[13] == 72 &&
      bytes[14] == 68 &&
      bytes[15] == 82;
}

void _resetProgressScroll(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('progress-overview-scroll')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
}

Future<void> _scrollProgressUntilVisible(
  WidgetTester tester,
  Finder target,
) async {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('progress-overview-scroll')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    target,
    260,
    scrollable: scrollable,
    maxScrolls: 12,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollActiveListUntilVisible(
  WidgetTester tester,
  Finder target,
) async {
  final list = find.byType(ListView).hitTestable().first;
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: scrollable,
    maxScrolls: 12,
  );
  await tester.pumpAndSettle();
}

void _resetActiveListScroll(WidgetTester tester) {
  final list = find.byType(ListView).hitTestable().first;
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _waitForExerciseProgress(
  WidgetTester tester,
  UiDesignFixture fixture,
) async {
  final viewModel = fixture.account.progressViewModel;
  for (
    var attempt = 0;
    attempt < 30 &&
        (viewModel.dashboard == null || viewModel.exerciseProgress == null);
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(viewModel.dashboard, isNotNull);
  expect(viewModel.selectedExerciseId, isNotNull);
  expect(viewModel.selectedProgressWindow, '30');
  expect(viewModel.exerciseOptions, isNotEmpty);
  expect(viewModel.exerciseProgress, isNotNull);
  expect(viewModel.exerciseProgress!.points, isNotEmpty);
}

Future<void> _savePreview(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Directory output,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) {
      throw StateError('Could not encode preview $name.');
    }
    await File('${output.path}/$name-windows-font-substitution.png')
        .writeAsBytes(png.buffer.asUint8List());
  });
}
