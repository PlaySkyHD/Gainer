# Tasks

## 1. Backend
- [x] 1.1 `Phases` (jsonb) und `TemplateName` an `CardioSession`; Migration, Validierung, Tests.

## 2. iOS
- [x] 2.1 Pigeon-Erweiterung (Phasen, Sprache), Phasenlogik im `CardioZoneAlarm`/Monitor, Benachrichtigungen, Live Activity mit Phase; XCTests.
- [x] 2.2 Sprachansagen (`AVSpeechSynthesizer`, Audio-Session, `UIBackgroundModes` `audio`); XCTests für Texte.

## 3. Flutter
- [x] 3.1 Vorlagenmodell, mitgelieferte Vorlagen, Auflösung von Zonen, Zeit im Ziel je Phase; Unit-Tests.
- [x] 3.2 Vorlagenwahl und -editor, Phasenanzeige in Live/Detail, Einstellungen (Anbieten, Sprache); Widget- und Golden-Tests.
- [x] 3.3 „Cardio anhängen“ in der Workout-Zusammenfassung; Tests.

## 4. Abschluss
- [x] 4.1 Analyse, Tests, Format, `openspec validate --strict`, CI grün.
- [x] 4.2 Abnahme auf dem iPhone: 4×4 mit gesperrtem Display und Musik.
