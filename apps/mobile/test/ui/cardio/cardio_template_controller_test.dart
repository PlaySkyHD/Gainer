import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_session_controller.dart';

import 'cardio_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CardioHarness harness;
  final t0 = DateTime.utc(2026, 10, 18, 10);

  late CardioSessionController controller;

  setUp(() async {
    harness = await CardioHarness.create(now: t0);
    controller = harness.controller;
  });

  tearDown(() async => harness.dispose());

  Future<void> prefs(CardioPreferenceValues values) =>
      harness.repository.preferences.write(values);

  test('start with template sends phases, voice options and no zone', () async {
    await prefs(
      const CardioPreferenceValues(
        maxHeartRate: 190,
        voiceEnabled: true,
        voiceIntervalMinutes: 5,
      ),
    );
    final draft = await controller.start(template: CardioTemplate.norwegian);

    expect(draft.templateName, '4×4 (Norwegisch)');
    expect(draft.phases, hasLength(9));
    expect(draft.targetZone, isNull);
    final config = harness.platform.started.single;
    expect(config.zoneLowBpm, isNull);
    expect(config.zoneHighBpm, isNull);
    expect(config.phases, hasLength(9));
    expect(
      config.phases[1].zone,
      const CardioTargetZone(lowBpm: 152, highBpm: 171),
    );
    expect(config.voiceEnabled, isTrue);
    expect(config.voiceIntervalMinutes, 5);

    // _rememberStart läuft unawaited; die Vorlage ist danach gemerkt.
    await pumpEventQueue();
    final values = await harness.repository.preferences.read();
    expect(values.lastTemplateId, CardioTemplate.norwegianId);
    expect(values.voiceEnabled, isTrue);
  });

  test(
    'voice interval is off without voice and default has no phases',
    () async {
      await prefs(const CardioPreferenceValues(voiceIntervalMinutes: 10));
      await controller.start(
        zone: const CardioTargetZone(lowBpm: 120, highBpm: 140),
      );
      final config = harness.platform.started.single;
      expect(config.voiceEnabled, isFalse);
      expect(config.voiceIntervalMinutes, 0);
      expect(config.phases, isEmpty);
      expect(config.zoneLowBpm, 120);
    },
  );

  test('zone template without zones fails and starts nothing', () async {
    await expectLater(
      controller.start(template: CardioTemplate.zone2),
      throwsA(isA<CardioTemplateResolutionException>()),
    );
    expect(controller.isRunning, isFalse);
    expect(harness.platform.started, isEmpty);
  });

  test('phase getters follow the elapsed time', () async {
    await prefs(const CardioPreferenceValues(maxHeartRate: 190));
    await controller.start(template: CardioTemplate.norwegian);

    expect(controller.hasTemplate, isTrue);
    expect(controller.phaseCount, 9);
    expect(controller.phaseIndex, 0);
    expect(controller.currentPhase!.name, 'Aufwärmen');
    expect(controller.phaseRemaining, const Duration(minutes: 10));
    expect(controller.nextPhase!.name, 'Belastung');
    expect(
      controller.currentZone,
      const CardioTargetZone(lowBpm: 114, highBpm: 133),
    );

    harness.now = t0.add(const Duration(minutes: 10, seconds: 46));
    expect(controller.phaseIndex, 1);
    expect(controller.currentPhase!.name, 'Belastung');
    expect(controller.phaseRemaining, const Duration(minutes: 3, seconds: 14));
    expect(
      controller.currentZone,
      const CardioTargetZone(lowBpm: 152, highBpm: 171),
    );
    expect(controller.templateFinished, isFalse);

    harness.now = t0.add(const Duration(hours: 1));
    expect(controller.currentPhase, isNull);
    expect(controller.phaseIndex, isNull);
    expect(controller.currentZone, isNull);
    expect(controller.templateFinished, isTrue);
    expect(controller.zoneState, HeartRateZoneState.none);
  });

  test('zone state uses the current phase zone', () async {
    await prefs(const CardioPreferenceValues(maxHeartRate: 190));
    await controller.start(template: CardioTemplate.norwegian);
    harness.platform
      ..latestBpm = 140
      ..latestAt = t0;
    await controller.poll();
    // Phase 1: 114-133, Puls 140 -> zu hoch.
    expect(controller.zoneState, HeartRateZoneState.above);

    harness.now = t0.add(const Duration(minutes: 10, seconds: 1));
    harness.platform
      ..latestBpm = 140
      ..latestAt = harness.now;
    await controller.poll();
    // Belastung: 152-171, Puls 140 -> zu niedrig.
    expect(controller.zoneState, HeartRateZoneState.below);
  });

  test('zone cannot be changed during a template', () async {
    await prefs(const CardioPreferenceValues(maxHeartRate: 190));
    await controller.start(template: CardioTemplate.norwegian);
    await expectLater(
      controller.updateZone(const CardioTargetZone(lowBpm: 100, highBpm: 120)),
      throwsStateError,
    );
  });

  test('finish stores template name, phases and longest-phase zone', () async {
    await prefs(const CardioPreferenceValues(maxHeartRate: 190));
    await controller.start(template: CardioTemplate.norwegian);
    harness.now = t0.add(const Duration(minutes: 5));
    final saved = await controller.finish();

    expect(saved.templateName, '4×4 (Norwegisch)');
    expect(saved.phases, hasLength(9));
    expect(saved.targetZone, const CardioTargetZone(lowBpm: 114, highBpm: 133));
    final stored = await harness.repository.readSessions();
    expect(stored.single.phases, hasLength(9));
    expect(stored.single.templateName, '4×4 (Norwegisch)');
  });

  test('restart after app kill restores template and phases', () async {
    await prefs(
      const CardioPreferenceValues(maxHeartRate: 190, voiceEnabled: true),
    );
    await controller.start(template: CardioTemplate.norwegian);
    final first = controller;

    // Neuer Controller wie nach einem App-Neustart; die native Seite kennt
    // die Einheit nicht mehr.
    harness.platform.monitoring = null;
    final second = CardioSessionController(
      repository: harness.repository,
      platform: harness.platform,
      notifications: FakeNotifications(),
      trainingPreferences: first.trainingPreferences,
      autoPoll: false,
      clock: () => harness.now,
    );
    addTearDown(second.dispose);
    await second.load();

    expect(second.active!.templateName, '4×4 (Norwegisch)');
    expect(second.active!.phases, hasLength(9));
    final restarted = harness.platform.started.last;
    expect(restarted.phases, hasLength(9));
    expect(restarted.zoneLowBpm, isNull);
    expect(restarted.voiceEnabled, isTrue);
  });

  test('startWithLastValues uses the last template or the last zone', () async {
    await prefs(
      const CardioPreferenceValues(
        maxHeartRate: 190,
        lastTemplateId: CardioTemplate.zone2Id,
        warmupSeconds: 60,
      ),
    );
    await controller.startWithLastValues();
    expect(controller.active!.templateName, 'Zone 2 – 30 min');
    expect(controller.active!.warmupSeconds, 60);
    await controller.discard();

    await prefs(
      const CardioPreferenceValues(lastZoneLow: 125, lastZoneHigh: 145),
    );
    await controller.startWithLastValues();
    expect(controller.active!.phases, isEmpty);
    expect(
      controller.active!.targetZone,
      const CardioTargetZone(lowBpm: 125, highBpm: 145),
    );
  });

  test('preferences round trip templates and new options', () async {
    const custom = CardioTemplate(
      id: 'tpl-1',
      name: 'Eigene',
      phases: [
        CardioTemplatePhase(
          name: 'A',
          durationSeconds: 120,
          target: CardioBpmTarget(120, 140),
        ),
      ],
    );
    await prefs(
      const CardioPreferenceValues(
        templates: [custom],
        lastTemplateId: 'tpl-1',
        offerAfterStrength: false,
        voiceEnabled: true,
        voiceIntervalMinutes: 2,
      ),
    );
    final back = await harness.repository.preferences.read();
    expect(back.templates, [custom]);
    expect(back.lastTemplate, custom);
    expect(back.offerAfterStrength, isFalse);
    expect(back.voiceEnabled, isTrue);
    expect(back.voiceIntervalMinutes, 2);
    expect(back.allTemplates, hasLength(3));
  });

  test('defaults and invalid stored templates', () async {
    const defaults = CardioPreferenceValues();
    expect(defaults.offerAfterStrength, isTrue);
    expect(defaults.voiceEnabled, isFalse);
    expect(defaults.voiceIntervalMinutes, 0);
    expect(defaults.allTemplates, CardioTemplate.builtIns);

    await harness.store.writeSyncMetadata('cardioPreferences', {
      'templates': [
        {'id': 'bad', 'name': '', 'phases': <Object>[]},
        'nonsense',
        CardioTemplate.zone2.copyWith(id: 'ok', name: 'Gut').toJson(),
        CardioTemplate.zone2.toJson(),
      ],
      'voiceIntervalMinutes': 3,
    });
    final back = await harness.repository.preferences.read();
    expect(back.templates.map((t) => t.id), ['ok']);
    expect(back.voiceIntervalMinutes, 0);
  });
}
