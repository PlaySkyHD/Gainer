import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/app.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('writes a 390 by 844 shell preview for visual review', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider<MobileShellViewModel>(
        create: (_) => MobileShellViewModel(),
        child: RepaintBoundary(
          key: boundaryKey,
          child: const GainerMobileApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      expect(png, isNotNull);

      final output = Directory('../../artifacts/mobile-preview');
      await output.create(recursive: true);
      await File('${output.path}/mobile-shell-390x844.png')
          .writeAsBytes(png!.buffer.asUint8List());
    });
  });
}
