import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/features/nutrition/meal_dictation_controller.dart';

void main() {
  test(
    'appends the transcript to typed text and waits for the final text',
    () async {
      final platform = _ScriptedDictation();
      final text = TextEditingController(text: 'Frühstück:');
      final controller = MealDictationController(
        platform: platform,
        text: text,
        pollInterval: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.isListening, isTrue);
      expect(platform.localeId, 'de-DE');

      platform.transcript = 'Müsli mit Milch';
      await _until(text, () => text.text == 'Frühstück: Müsli mit Milch');
      expect(text.text, 'Frühstück: Müsli mit Milch');

      platform.onStop = () => platform.transcript = 'Müsli mit Milch, 300 g.';
      await controller.finish();
      expect(controller.isListening, isFalse);
      expect(text.text, 'Frühstück: Müsli mit Milch, 300 g.');
      expect(controller.message, isNull);
    },
  );

  test('explains denied and unavailable dictation without listening', () async {
    for (final status in [
      DictationStatus.denied,
      DictationStatus.unavailable,
    ]) {
      final controller = MealDictationController(
        platform: _ScriptedDictation(startStatus: status),
        text: TextEditingController(),
      );
      await controller.start();
      expect(controller.isListening, isFalse);
      expect(controller.message, isNotNull);
      controller.dispose();
    }
  });

  test('a failed recognition without text reports a hint', () async {
    final platform = _ScriptedDictation();
    final controller = MealDictationController(
      platform: platform,
      text: TextEditingController(),
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);
    await controller.start();
    platform.status = DictationStatus.failed;
    await _until(controller, () => !controller.isListening);
    expect(controller.isListening, isFalse);
    expect(controller.message, contains('nichts erkannt'));
  });

  test('dispose cancels a running dictation', () async {
    final platform = _ScriptedDictation();
    final controller = MealDictationController(
      platform: platform,
      text: TextEditingController(),
    );
    await controller.start();
    controller.dispose();
    expect(platform.cancelled, isTrue);
  });

  test('cancel while the microphone is still starting stops it', () async {
    final platform = _SlowStartDictation();
    final controller = MealDictationController(
      platform: platform,
      text: TextEditingController(),
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);

    final starting = controller.start();
    expect(controller.isStarting, isTrue);
    controller.cancel();
    platform.release.complete();
    await starting;

    expect(platform.cancelled, isTrue);
    expect(controller.isListening, isFalse);
    expect(controller.isStarting, isFalse);
  });

  test('finish while the microphone is still starting cancels the start '
      'and no dictation writes afterwards', () async {
    final platform = _SlowStartDictation();
    final text = TextEditingController(text: 'Müsli');
    final controller = MealDictationController(
      platform: platform,
      text: text,
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);

    final starting = controller.start();
    var finished = false;
    final finishing = controller.finish().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    // Solange die Plattform noch startet, ist das Ende nicht erreicht.
    expect(finished, isFalse);

    platform.transcript = 'Spät diktiert';
    platform.release.complete();
    await starting;
    await finishing;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(platform.cancelled, isTrue);
    expect(controller.isListening, isFalse);
    expect(text.text, 'Müsli');
  });
}

/// Wartet ohne feste Zeit, bis [done] wahr wird; prüft bei jeder Änderung von
/// [source]. Die Obergrenze verhindert nur ein Hängen bei einem echten Fehler.
Future<void> _until(Listenable source, bool Function() done) {
  if (done()) return Future.value();
  final completer = Completer<void>();
  void check() {
    if (done() && !completer.isCompleted) completer.complete();
  }

  source.addListener(check);
  return completer.future
      .timeout(const Duration(seconds: 10))
      .whenComplete(() => source.removeListener(check));
}

class _SlowStartDictation extends _ScriptedDictation {
  final release = Completer<void>();

  @override
  Future<DictationState> startDictation({required String localeId}) async {
    await release.future;
    return super.startDictation(localeId: localeId);
  }
}

class _ScriptedDictation implements DictationPlatform {
  _ScriptedDictation({this.startStatus = DictationStatus.listening});

  final DictationStatus startStatus;
  DictationStatus status = DictationStatus.idle;
  String transcript = '';
  String? localeId;
  bool cancelled = false;
  void Function()? onStop;

  @override
  Future<DictationState> startDictation({required String localeId}) async {
    this.localeId = localeId;
    status = startStatus;
    return _state;
  }

  @override
  Future<DictationState> readDictation() async => _state;

  @override
  Future<void> stopDictation() async {
    onStop?.call();
    status = DictationStatus.finished;
  }

  @override
  Future<void> cancelDictation() async {
    cancelled = true;
    status = DictationStatus.idle;
  }

  DictationState get _state =>
      DictationState(status: status, transcript: transcript);
}
