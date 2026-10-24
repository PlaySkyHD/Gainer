# Design

## Decisions

### D1 – Plattformschnittstelle

`HealthPlatform` erhält:

- `requestCheckInAuthorization()` – fragt Lesen (Gewicht, Schritte, Schlaf) und Schreiben (Gewicht, Schlaf) in einem Systemdialog an.
- `readStepCount({fromUtc, toUtc})` → `int?` (Summe per `HKStatisticsQuery`, `cumulativeSum`; null ohne Daten).
- `readSleep({fromUtc, toUtc})` → `HealthSleepWindow?` mit `bedtimeUtc`, `wakeUtc`, `asleepMinutes`, `sourceName` aus `HKCategoryType.sleepAnalysis`. Schlafphasen (`asleepUnspecified/Core/Deep/REM`) zählen als Schlaf; Zu Bett = frühester Beginn, Aufgestanden = spätestes Ende.
- `writeBodyMass({kilograms, measuredAtUtc, syncIdentifier})` und `writeSleep({bedtimeUtc, wakeUtc, syncIdentifier})` → `HealthWriteStatus` (`saved`, `alreadyPresent`, `notAuthorized`). Gespeichert wird mit `HKMetadataKeySyncIdentifier` und `HKMetadataKeySyncVersion`, sodass erneutes Speichern desselben Check-ins die Probe ersetzt statt sie zu verdoppeln.

Gewicht wird weiter über das vorhandene `readBodyMassSamples` gelesen.

### D2 – Zeitfenster

- Tag: lokale Mitternacht bis nächste lokale Mitternacht, für heute begrenzt auf jetzt (wie beim Gewichtsimport).
- Nacht zum Check-in-Tag: 18:00 des Vortags bis 14:00 des Tags (lokal), ebenfalls höchstens bis jetzt.

### D3 – Schreiben nach Health

Beim Speichern eines Check-ins:
- Gewicht wird geschrieben, wenn das Lesen für den Tag keine Health-Probe aus einer anderen Quelle als Gainer ergab.
- Schlaf wird geschrieben, wenn Zu Bett/Aufgestanden manuell gesetzt sind und für die Nacht keine fremde Schlafanalyse vorliegt.
- `syncIdentifier` = `gainer-checkin-<accountId>-<localDate>-weight|sleep`, `syncVersion` = Millisekunden des Speicherzeitpunkts.
- Fehler oder fehlende Berechtigung beim Schreiben verhindern das Speichern des Check-ins nicht; sie werden still protokolliert.

### D4 – Oberfläche

Check-in-Sheet: Datum (`GainerDateRow`), Gruppe „Gewicht“ (`GainerTextFieldRow` kg, Fußnote „aus Apple Health“ wenn vorausgefüllt), Gruppe „Schlaf“ mit zwei Zeitzeilen „Zu Bett“ und „Aufgestanden“ (Uhrzeit-Picker im Sheet) und Dauerzeile („7 h 30 min“), Gruppe „Schritte“ als reine Anzeige („8.432“ bzw. „Keine Daten aus Apple Health“). Bestehende Kalorien-/Makrowerte eines alten Check-ins bleiben beim Speichern unverändert erhalten.

## Risks / Trade-offs

- HealthKit verrät keine Lese-Berechtigung → leere Werte bedeuten „keine Daten oder kein Zugriff“; die UI formuliert neutral.
- Swift lässt sich nur in CI bauen → Swift-Logik klein halten, Fensterberechnung und Entscheidungen in Dart mit Tests.
