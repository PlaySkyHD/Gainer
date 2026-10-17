import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/ui_design_fixture.dart';
import '../../../integration_test/ui_design_flow.dart';

const _previewNames = [
  'tab-heute',
  'exercise-progress',
  'tab-checkin',
  'sheet-checkin',
  'sheet-goal',
  'date-picker',
  'tab-essen',
  'editor-essen',
  'tab-training',
  'training-workout',
  'training-minimized',
  'tab-mehr',
  'tab-dark-heute',
  'tab-dark-checkin',
  'tab-dark-essen',
  'tab-dark-training',
  'tab-dark-mehr',
  'sheet-dark-checkin',
  'editor-dark-essen',
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

      await runUiDesignCaptureFlow(
        tester,
        fixture,
        (theme) => RepaintBoundary(key: boundaryKey, child: fixture.app(theme)),
        (name) => _savePreview(tester, boundaryKey, output, name),
      );

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
