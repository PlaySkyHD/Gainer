import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_sound.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';

import '../../ui/training/training_test_support.dart';

void main() {
  late TrainingHarness harness;
  late TrainingPreferences preferences;

  setUp(() async {
    harness = await TrainingHarness.create();
    preferences = TrainingPreferences(store: harness.store);
  });

  tearDown(() => harness.dispose());

  test('Timereinstellungen haben Standardwerte', () async {
    final values = await preferences.read();

    expect(values.timerSoundId, 'digital_alarm');
    expect(values.autoStartRestTimer, isFalse);
    expect(preferences.timerSoundId.value, 'digital_alarm');
    expect(preferences.autoStartRestTimer.value, isFalse);
  });

  test('Ton und Auto-Start werden gespeichert und veröffentlicht', () async {
    await preferences.write(
      const TrainingPreferenceValues(
        timerSoundId: 'gong',
        autoStartRestTimer: true,
      ),
    );

    final reread = TrainingPreferences(store: harness.store);
    final values = await reread.read();
    expect(values.timerSoundId, 'gong');
    expect(values.autoStartRestTimer, isTrue);
    expect(reread.timerSoundId.value, 'gong');
    expect(reread.autoStartRestTimer.value, isTrue);
  });

  test(
    'unbekannte gespeicherte Sound-ID fällt auf den Standard zurück',
    () async {
      await harness.store.writeSyncMetadata('trainingPreferences', {
        'timerSoundId': 'does_not_exist',
        'autoStartRestTimer': 'yes',
      });

      final values = await preferences.read();

      expect(values.timerSoundId, RestTimerSound.defaultId);
      expect(values.autoStartRestTimer, isFalse);
    },
  );

  test(
    'update ändert nur das Gewünschte und erhält die übrigen Werte',
    () async {
      await preferences.write(
        const TrainingPreferenceValues(
          showRir: true,
          weightUnit: WeightUnit.lbs,
        ),
      );

      await preferences.update((v) => v.copyWith(timerSoundId: 'radar'));
      await preferences.update((v) => v.copyWith(autoStartRestTimer: true));
      await preferences.update((v) => v.copyWith(autoStartRestTimer: true));

      final values = await TrainingPreferences(store: harness.store).read();
      expect(values.showRir, isTrue);
      expect(values.weightUnit, WeightUnit.lbs);
      expect(values.timerSoundId, 'radar');
      expect(values.autoStartRestTimer, isTrue);
    },
  );

  test('Gleichheit und Hash berücksichtigen die Timerwerte', () {
    const a = TrainingPreferenceValues(timerSoundId: 'gong');
    const b = TrainingPreferenceValues(timerSoundId: 'gong');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == a.copyWith(autoStartRestTimer: true), isFalse);
    expect(a == a.copyWith(timerSoundId: 'chime'), isFalse);
    expect(a.toJson()['timerSoundId'], 'gong');
  });

  test('alle Töne haben eine eindeutige ID und eine Bezeichnung', () {
    final ids = RestTimerSound.all.map((s) => s.id).toSet();
    expect(ids, hasLength(RestTimerSound.all.length));
    expect(ids, contains(RestTimerSound.defaultId));
    expect(ids, contains('system'));
    expect(RestTimerSound.all.every((s) => s.label.isNotEmpty), isTrue);
    expect(RestTimerSound.resolveId(null), RestTimerSound.defaultId);
    expect(RestTimerSound.resolveId('gong'), 'gong');
  });
}
