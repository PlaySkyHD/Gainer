import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_live_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_settings_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_start_sheet.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_template_screens.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

void main() {
  late CardioHarness harness;
  final t0 = DateTime.utc(2026, 10, 18, 10);

  setUp(() async {
    harness = await CardioHarness.create(now: t0);
  });

  tearDown(() async => harness.dispose());

  Future<void> writePrefs(WidgetTester tester, CardioPreferenceValues v) async {
    await tester.runAsync(() => harness.repository.preferences.write(v));
  }

  Future<CardioPreferenceValues> stored(WidgetTester tester) async =>
      (await tester.runAsync(harness.repository.preferences.read))!;

  Future<void> openFrom(
    WidgetTester tester,
    void Function(BuildContext context) open, {
    double textScale = 1,
    double height = 844,
  }) async {
    phoneSize(tester, height: height);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUi(tester);
  }

  GainerPillButton button(WidgetTester tester, String key) =>
      tester.widget<GainerPillButton>(find.byKey(ValueKey(key)));

  group('Start-Sheet', () {
    Future<void> openSheet(WidgetTester tester, {double textScale = 1}) =>
        openFrom(
          tester,
          (context) => showCardioStartSheet(context, harness.feature),
          textScale: textScale,
        );

    Future<void> pickTemplate(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const ValueKey('cardio-start-template')));
      await pumpUi(tester);
      await tester.tap(find.text(name));
      await pumpUi(tester);
    }

    testWidgets('Vorlage ersetzt den Zielbereich durch die Phasenliste', (
      tester,
    ) async {
      await writePrefs(tester, const CardioPreferenceValues(maxHeartRate: 190));
      await openSheet(tester);
      expect(find.text('Freie Einheit'), findsOneWidget);
      expect(find.byKey(const ValueKey('cardio-zone-low')), findsOneWidget);

      await pickTemplate(tester, '4×4 (Norwegisch)');

      expect(find.byKey(const ValueKey('cardio-zone-low')), findsNothing);
      expect(find.text('Aufwärmen 10:00 · Zone 2 · 114–133'), findsOneWidget);
      expect(find.text('Belastung 4:00 · Zone 4 · 152–171'), findsNWidgets(4));
      expect(find.text('Ausfahren 5:00 · Zone 1 · 95–114'), findsOneWidget);
      expect(find.textContaining('9 Phasen · 40 min'), findsOneWidget);
      expect(button(tester, 'cardio-start').onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const ValueKey('cardio-start')));
      await tester.tap(find.byKey(const ValueKey('cardio-start')));
      await pumpUi(tester);
      expect(harness.controller.active!.templateName, '4×4 (Norwegisch)');
      expect(harness.platform.started.single.phases, hasLength(9));
    });

    testWidgets(
      'Zonenvorlage ohne Zonen sperrt Starten und erklärt den Grund',
      (tester) async {
        await openSheet(tester);
        await pickTemplate(tester, 'Zone 2 – 30 min');

        expect(button(tester, 'cardio-start').onPressed, isNull);
        expect(find.text('Zonen fehlen'), findsOneWidget);
        expect(
          find.textContaining('in den Cardio-Einstellungen an'),
          findsOneWidget,
        );
        // Zurück zur freien Einheit: Starten geht wieder.
        await pickTemplate(tester, 'Freie Einheit');
        expect(button(tester, 'cardio-start').onPressed, isNotNull);
        expect(find.byKey(const ValueKey('cardio-zone-low')), findsOneWidget);
      },
    );

    testWidgets('merkt die zuletzt genutzte Vorlage', (tester) async {
      await writePrefs(
        tester,
        const CardioPreferenceValues(
          maxHeartRate: 190,
          lastTemplateId: CardioTemplate.zone2Id,
        ),
      );
      await openSheet(tester);
      expect(find.text('Zone 2 – 30 min'), findsOneWidget);
      expect(find.text('Zone 2 30:00 · Zone 2 · 114–133'), findsOneWidget);
    });

    testWidgets('Textgröße 2: Vorlagenliste läuft nicht über', (tester) async {
      await writePrefs(
        tester,
        const CardioPreferenceValues(
          maxHeartRate: 190,
          lastTemplateId: CardioTemplate.norwegianId,
        ),
      );
      await openSheet(tester, textScale: 2);
      expect(find.byKey(const ValueKey('cardio-start-template')), findsOne);
      expect(tester.takeException(), isNull);
    });
  });

  group('Live-Ansicht', () {
    Future<void> startTemplate(
      WidgetTester tester, {
      Duration after = Duration.zero,
    }) async {
      await tester.runAsync(() async {
        await harness.repository.preferences.write(
          const CardioPreferenceValues(maxHeartRate: 190),
        );
        await harness.controller.start(template: CardioTemplate.norwegian);
        harness.now = t0.add(after);
        harness.platform
          ..latestBpm = 120
          ..latestAt = harness.now;
        await harness.controller.poll();
      });
    }

    Future<void> openLive(WidgetTester tester, {double textScale = 1}) =>
        openFrom(
          tester,
          (context) => openCardioLive(context, harness.feature),
          textScale: textScale,
        );

    String textOf(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    testWidgets('zeigt Phase, Restzeit, Ziel und die nächste Phase', (
      tester,
    ) async {
      await startTemplate(
        tester,
        after: const Duration(minutes: 10, seconds: 46),
      );
      await openLive(tester);

      expect(textOf(tester, 'cardio-phase-title'), 'Phase 2/9 · Belastung');
      expect(textOf(tester, 'cardio-phase-countdown'), '3:14');
      expect(textOf(tester, 'cardio-phase-target'), 'Ziel 152–171 bpm');
      expect(textOf(tester, 'cardio-phase-next'), 'Nächste: Erholung 3:00');
      expect(find.text('152–171 bpm'), findsOneWidget);
      expect(
        find.text('Die Phasen der Vorlage bestimmen das Ziel.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zielbereich lässt sich bei einer Vorlage nicht ändern', (
      tester,
    ) async {
      await startTemplate(tester);
      await openLive(tester);
      await tester.tap(find.byKey(const ValueKey('cardio-live-zone')));
      await pumpUi(tester);
      expect(find.text('Zielbereich ändern'), findsNothing);
    });

    testWidgets('nach der letzten Phase läuft die Einheit ohne Ziel weiter', (
      tester,
    ) async {
      await startTemplate(tester, after: const Duration(minutes: 60));
      await openLive(tester);

      expect(find.byKey(const ValueKey('cardio-phase-finished')), findsOne);
      expect(
        find.text('Vorlage beendet – du kannst beenden oder weiterfahren.'),
        findsOneWidget,
      );
      expect(find.text('Kein Zielbereich'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cardio-phase-countdown')),
        findsNothing,
      );
    });

    testWidgets('Textgröße 2 ohne Überlauf', (tester) async {
      await startTemplate(
        tester,
        after: const Duration(minutes: 10, seconds: 46),
      );
      await openLive(tester, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Editor', () {
    testWidgets('Sichern ist erst mit Name und gültiger Phase aktiv', (
      tester,
    ) async {
      CardioTemplate? result;
      await openFrom(tester, (context) async {
        result = await showCardioTemplateEditor(context);
      });

      expect(find.text('Neue Vorlage'), findsOneWidget);
      expect(button(tester, 'cardio-template-save').onPressed, isNull);
      expect(find.text('Der Name fehlt.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('cardio-template-name')),
        'Intervalle',
      );
      await tester.pump();
      expect(button(tester, 'cardio-template-save').onPressed, isNotNull);
      expect(find.byKey(const ValueKey('cardio-template-error')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('cardio-template-save')));
      await pumpUi(tester);
      expect(result!.name, 'Intervalle');
      expect(result!.phases, hasLength(1));
      expect(result!.validate(), isNull);
    });

    testWidgets('Phase hinzufügen, ändern und Bereichsfehler', (tester) async {
      CardioTemplate? result;
      await openFrom(tester, (context) async {
        result = await showCardioTemplateEditor(
          context,
          template: CardioTemplate.zone2.copyWith(id: 'x', name: 'Kopie'),
        );
      }, height: 1200);

      await tester.tap(find.byKey(const ValueKey('cardio-template-add-phase')));
      await pumpUi(tester);
      expect(find.text('Neue Phase'), findsOneWidget);

      // bpm-Ziel mit ungültigem Bereich.
      await tester.tap(find.text('bpm'));
      await pumpUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('cardio-phase-low')),
        '150',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cardio-phase-high')),
        '140',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('cardio-phase-error')), findsOneWidget);
      expect(button(tester, 'cardio-phase-save').onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('cardio-phase-high')),
        '160',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('cardio-phase-error')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('cardio-phase-save')));
      await pumpUi(tester);

      expect(find.text('Erholung'), findsOneWidget);
      expect(find.text('5:00 · 150–160 bpm'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cardio-template-save')));
      await pumpUi(tester);
      expect(result!.phases, hasLength(2));
      expect(result!.phases.last.target, const CardioBpmTarget(150, 160));
    });

    testWidgets('mehr als 30 Phasen sind nicht möglich', (tester) async {
      final template = CardioTemplate(
        id: 'x',
        name: 'Viele',
        phases: [
          for (var i = 0; i < 30; i++)
            CardioTemplatePhase(name: 'P$i', durationSeconds: 60),
        ],
      );
      await openFrom(
        tester,
        (context) => showCardioTemplateEditor(context, template: template),
        height: 3000,
      );
      expect(
        tester
            .widget<GainerListRow>(
              find.byKey(const ValueKey('cardio-template-add-phase')),
            )
            .onTap,
        isNull,
      );
      expect(find.textContaining('Mehr als 30 Phasen'), findsOneWidget);
    });

    testWidgets('lange Phase: Vorlage über 4 Stunden wird abgewiesen', (
      tester,
    ) async {
      final template = CardioTemplate(
        id: 'x',
        name: 'Lang',
        phases: [
          for (var i = 0; i < 5; i++)
            const CardioTemplatePhase(name: 'P', durationSeconds: 3000),
        ],
      );
      await openFrom(
        tester,
        (context) => showCardioTemplateEditor(context, template: template),
        height: 1200,
      );
      expect(find.textContaining('höchstens 4 Stunden'), findsOneWidget);
      expect(button(tester, 'cardio-template-save').onPressed, isNull);
    });

    testWidgets('Textgröße 2 ohne Überlauf', (tester) async {
      await openFrom(
        tester,
        (context) => showCardioTemplateEditor(
          context,
          template: CardioTemplate.norwegian.copyWith(id: 'x', name: 'Kopie'),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Vorlagenliste', () {
    Future<void> openList(WidgetTester tester) async {
      phoneSize(tester, height: 1200);
      await tester.pumpWidget(
        trainingTestApp(
          home: CardioTemplatesScreen(
            preferences: harness.repository.preferences,
          ),
        ),
      );
      await pumpUi(tester);
    }

    testWidgets(
      'zeigt mitgelieferte Vorlagen, Duplizieren legt eine Kopie an',
      (tester) async {
        await openList(tester);
        expect(find.text('Zone 2 – 30 min'), findsOneWidget);
        expect(find.text('4×4 (Norwegisch)'), findsOneWidget);
        expect(find.text('9 Phasen · 40 min'), findsOneWidget);
        expect(find.textContaining('Noch keine eigenen'), findsOneWidget);

        await tester.longPress(find.text('4×4 (Norwegisch)'));
        await pumpUi(tester);
        expect(find.text('Löschen'), findsNothing);
        expect(find.text('Bearbeiten'), findsNothing);
        await tester.tap(find.text('Duplizieren'));
        await pumpUi(tester);

        final values = await stored(tester);
        expect(values.templates, hasLength(1));
        expect(values.templates.single.name, '4×4 (Norwegisch) Kopie');
        expect(values.templates.single.builtIn, isFalse);
        expect(values.templates.single.phases, hasLength(9));
        expect(find.text('4×4 (Norwegisch) Kopie'), findsOneWidget);
      },
    );

    testWidgets('Wischen löscht eine eigene Vorlage nach Bestätigung', (
      tester,
    ) async {
      final custom = CardioTemplate.zone2.copyWith(
        id: 'tpl-1',
        name: 'Meine Vorlage',
      );
      await writePrefs(tester, CardioPreferenceValues(templates: [custom]));
      await openList(tester);
      expect(find.text('Meine Vorlage'), findsOneWidget);

      await tester.drag(find.text('Meine Vorlage'), const Offset(-500, 0));
      await pumpUi(tester);
      await tester.tap(inDialog('Löschen'));
      await pumpUi(tester);

      expect(find.text('Meine Vorlage'), findsNothing);
      expect((await stored(tester)).templates, isEmpty);
    });

    testWidgets('mitgelieferte Vorlagen lassen sich nicht wegwischen', (
      tester,
    ) async {
      await openList(tester);
      await tester.drag(find.text('Zone 2 – 30 min'), const Offset(-500, 0));
      await pumpUi(tester);
      expect(find.text('Zone 2 – 30 min'), findsOneWidget);
    });

    testWidgets('Tippen bearbeitet, + legt neu an', (tester) async {
      final custom = CardioTemplate.zone2.copyWith(
        id: 'tpl-1',
        name: 'Meine Vorlage',
      );
      await writePrefs(tester, CardioPreferenceValues(templates: [custom]));
      await openList(tester);

      await tester.tap(find.text('Meine Vorlage'));
      await pumpUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('cardio-template-name')),
        'Umbenannt',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cardio-template-save')));
      await pumpUi(tester);
      var values = await stored(tester);
      expect(values.templates.single.name, 'Umbenannt');
      expect(values.templates.single.id, 'tpl-1');

      await tester.tap(find.bySemanticsLabel('Neue Vorlage'));
      await pumpUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('cardio-template-name')),
        'Neu',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cardio-template-save')));
      await pumpUi(tester);
      values = await stored(tester);
      expect(values.templates.map((t) => t.name), ['Umbenannt', 'Neu']);
    });
  });

  group('Einstellungen', () {
    Future<void> openSettings(WidgetTester tester) async {
      phoneSize(tester, height: 2400);
      await tester.pumpWidget(
        trainingTestApp(
          home: CardioSettingsScreen(
            preferences: harness.repository.preferences,
          ),
        ),
      );
      await pumpUi(tester);
    }

    testWidgets('Anbieten ist an, Sprache aus; Schalter speichern', (
      tester,
    ) async {
      await openSettings(tester);

      CupertinoSwitch toggle(String key) =>
          tester.widget<CupertinoSwitch>(find.byKey(ValueKey(key)));
      expect(toggle('cardio-settings-offer').value, isTrue);
      expect(toggle('cardio-settings-voice').value, isFalse);

      await tester.tap(find.byKey(const ValueKey('cardio-settings-offer')));
      await pumpUi(tester);
      expect((await stored(tester)).offerAfterStrength, isFalse);

      await tester.tap(find.byKey(const ValueKey('cardio-settings-voice')));
      await pumpUi(tester);
      expect((await stored(tester)).voiceEnabled, isTrue);
    });

    testWidgets('Intervall ist nur mit Sprachansagen wählbar', (tester) async {
      await openSettings(tester);
      bool ignoring() => tester
          .widget<IgnorePointer>(
            find.byKey(const ValueKey('cardio-settings-voice-interval')),
          )
          .ignoring;

      expect(ignoring(), isTrue);
      expect(find.text('Regelmäßige Ansage in Minuten'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cardio-settings-voice')));
      await pumpUi(tester);
      expect(ignoring(), isFalse);

      Finder inInterval(String label) => find.descendant(
        of: find.byKey(const ValueKey('cardio-settings-voice-interval')),
        matching: find.text(label),
      );
      await tester.tap(inInterval('5'));
      await pumpUi(tester);
      expect((await stored(tester)).voiceIntervalMinutes, 5);

      await tester.tap(inInterval('Aus'));
      await pumpUi(tester);
      expect((await stored(tester)).voiceIntervalMinutes, 0);
    });

    testWidgets('Vorlagen-Zeile öffnet die Liste', (tester) async {
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('cardio-settings-templates')));
      await pumpUi(tester);
      expect(find.text('Mitgeliefert'), findsOneWidget);
      expect(find.text('4×4 (Norwegisch)'), findsOneWidget);
    });
  });
}
