# Proposal

## Why

Eine Mahlzeit für die Schätzung einzutippen ist mühsam, gerade bei mehreren Bestandteilen und Mengen. Sprechen ist schneller.

## What Changes

- Unter „Mahlzeit schätzen“ gibt es den Button „Diktieren“. Während der Aufnahme heißt er „Fertig“.
- Die iOS-Spracherkennung (`SFSpeechRecognizer`, Deutsch) läuft nur auf dem Gerät und schreibt live in das Feld „Beschreibung“. Vorhandener Text bleibt stehen, das Diktat wird angehängt.
- Das Feld „Beschreibung“ ist mehrzeilig, damit der diktierte Text sichtbar bleibt.
- Geschätzt wird wie bisher erst auf Tippen von „Mahlzeit schätzen“. Ein laufendes Diktat wird dabei beendet und sein endgültiger Text übernommen.

### Non-Goals

- Kein Audio-Upload, keine Transkription auf dem Server, keine Backend-Änderung.
- Kein Diktat in anderen Feldern.

## Capabilities

- **Neu:** `meal-dictation`.

## Impact

- iOS: `NativeDictation.swift` (neu, im Xcode-Projekt eingetragen), Pigeon-Methoden `startDictation`, `readDictation`, `stopDictation` und `cancelDictation`. In `Info.plist` kommen `NSMicrophoneUsageDescription` und `NSSpeechRecognitionUsageDescription` hinzu.
- Flutter: `DictationPlatform`, `MealDictationController`, Button und Hinweise im Schätzen-Sheet. `GainerTextFieldRow` bekommt `maxLines`.
