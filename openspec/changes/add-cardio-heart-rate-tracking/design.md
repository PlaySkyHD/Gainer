# Design

## Context

Krafttrainings sind die Ressource `Workout` mit Sätzen. Cardio hat eine andere Form: Zeitreihe statt Sätze, keine Pläne, keine Vorwerte. Deshalb ist Cardio eine eigene Ressource und kein Sonderfall von `Workout`. Die App ist iOS-only. Nativer Code läuft über Pigeon und wird nur in der CI gebaut.

## Decisions

### D1 – Fachdaten `CardioSession`

| Feld | Typ | Regel |
|---|---|---|
| `sessionId` | UUID | Pflicht |
| `activityType` | String | `IndoorCycling` (später `Running` u. a.) |
| `startedAtUtc`, `endedAtUtc` | UTC | Ende nach Start, Dauer ≤ 24 h |
| `targetZone` | `{lowBpm, highBpm}` oder null | 40 ≤ low < high ≤ 230 |
| `sampleIntervalSeconds` | int | 1–60, App nutzt 5 |
| `heartRateBpm` | int[] | je Intervall ein Wert, 0 = kein Signal, sonst 25–250; Länge ≤ Dauer / Intervall + 1 |
| `rrIntervalsMs` | int[] | 200–3000, höchstens 40 000 Werte |
| `sensorName` | String? | ≤ 100 Zeichen |
| `distanceKm`, `averagePowerWatts`, `energyKcal` | decimal? | ≥ 0, manuell |
| `notes` | String? | ≤ 2 000 Zeichen |

Eine Einheit von 60 min ergibt 720 Pulswerte und etwa 8 000 RR-Werte, also rund 40 KB JSON. Das liegt deutlich unter dem Request-Limit von 1 MB.

Das Backend speichert die Reihen als PostgreSQL-`integer[]`-Spalten in `training.cardio_sessions`. Eine Tabelle je Messpunkt wäre für eine nur gelesene Zeitreihe überdimensioniert. Löschen ist ein hartes Löschen mit Löschmarke im Change-Feed (wie `NutritionDay`).

### D2 – Kennzahlen

Ø-Puls, Maximum, Zeit im Zielbereich, aktive Dauer und RMSSD berechnet die App deterministisch aus den gespeicherten Reihen (`CardioAnalysis`). Das weicht bewusst von „Analytics im Backend“ ab: Die Werte müssen offline direkt nach der Einheit sichtbar sein. Das Backend speichert die Rohdaten unverändert, damit eine spätere serverseitige Auswertung dieselbe Basis hat.

- **Ø/Max:** über alle Werte > 0.
- **Zeit im Zielbereich:** Anzahl Werte mit low ≤ bpm ≤ high × Intervall.
- **RMSSD:** RR-Werte außerhalb 300–2 000 ms verwerfen. Eine Differenz zählt nur, wenn beide Nachbarwerte gültig sind und sich um höchstens 20 % unterscheiden. Unter 30 gültigen Differenzen gibt es keinen Wert. Ergebnis auf ganze ms gerundet.

### D3 – Pulsgurt (iOS, CoreBluetooth)

- `NativeHeartRateMonitor` nutzt den Heart Rate Service `0x180D`, Measurement `0x2A37` und Battery `0x180F`/`0x2A19`.
- `HeartRateMeasurementParser` liest Flags, bpm (UInt8/UInt16), überspringt Energy Expended und wandelt RR-Werte (1/1024 s) in ms um. Er bekommt eigene XCTests.
- **Suchen:** `scanHeartRateSensors(durationMs)` liefert nach der Suchdauer die gefundenen Gurte. Dazu kommen Gurte, die schon mit dem System verbunden sind (`retrieveConnectedPeripherals`). Die Polar H10 kann zwei Verbindungen gleichzeitig halten.
- **Verbinden:** `connectHeartRateSensor(id)` merkt sich die ID in `UserDefaults`. Bricht die Verbindung ab, startet Swift sofort einen neuen `connect` ohne Timeout. iOS verbindet, sobald der Gurt wieder sendet.
- **Hintergrund:** `UIBackgroundModes` erhält `bluetooth-central`. Nur dann kommen Messwerte bei gesperrtem Display an.
- **Berechtigung:** `NSBluetoothAlwaysUsageDescription`. Ist Bluetooth aus oder verweigert, zeigt die App den Grund und einen Weg in die Einstellungen.

### D4 – Aufzeichnung und Zonenalarm laufen nativ

Dart läuft bei gesperrtem Display nicht zuverlässig. Deshalb liegen Puffer und Alarm in Swift:

- `startCardioMonitoring(config)` startet für eine `sessionId` einen Puffer mit allen Messwerten (Zeitstempel, bpm, RR). Jeder Messwert erhält eine Sequenznummer.
- `readHeartRateStatus(afterSequence)` liefert Verbindungszustand, Gurtname, Akku, letzten Puls und die Messwerte nach der Sequenz. Dart fragt im Vordergrund jede Sekunde und beim Zurückkehren in die App.
- `updateCardioMonitoring(config)` ändert den Zielbereich. `stopCardioMonitoring()` beendet Puffer und Alarm.
- **Zonenlogik** (`CardioZoneAlarm`, rein, mit XCTests):
  - Ist der Puls länger als `graceSeconds` (15) außerhalb, folgt eine Benachrichtigung „Puls zu hoch“ bzw. „Puls zu niedrig“ mit aktuellem Wert und Zielbereich, mit Ton.
  - Bleibt der Puls draußen, wiederholt sie sich höchstens alle `repeatSeconds` (60).
  - Nach einem Alarm meldet eine Benachrichtigung ohne Ton „Wieder im Zielbereich“.
  - In den ersten `warmupSeconds` (Standard 180, einstellbar 0–600) gibt es keinen Alarm.
  - Kommen 30 s keine Werte, gibt es einmal „Kein Pulssignal“.
- Benachrichtigungen nutzen das Präfix `com.gainer.mobile.cardio.`. `TimerNotificationDelegate` zeigt sie auch bei geöffneter App als Banner mit Ton. Der Ton ist der gewählte Timerton.

### D5 – Ablauf in der App

- **Laufende Einheit:** Es gibt höchstens eine laufende Cardio-Einheit. Sie läuft unabhängig von einem aktiven Krafttraining.
- **Entwurf:** Die laufende Einheit liegt nur lokal als Entwurf in den Sync-Metadaten (`cardio-active-session`). Er enthält Start, Zielbereich, Gurt, die schon zu 5-s-Werten verdichteten Pulswerte, die RR-Werte und die letzte gelesene Sequenz. Dart verdichtet die Messwerte: Mittelwert aller Werte im Intervall, 0 ohne Wert.
- **Beenden:** „Beenden“ schreibt eine `CardioSession` per `commitMutation` (Operation `create`), löscht den Entwurf und stoppt die native Überwachung. Unter 60 s fragt die App, ob die Einheit verworfen werden soll.
- **App beendet:** Startet die App mit einem Entwurf, zeigt das Tagebuch „Cardio läuft“. Ist die native Überwachung weg (`readHeartRateStatus` kennt die Session nicht), startet Dart sie mit dem Entwurf neu. Nur die Messwerte seit dem letzten Lesen gehen verloren.
- **Bearbeiten:** Notiz und manuelle Werte bearbeiten erzeugt `update`, Löschen erzeugt `delete`. Beides läuft wie bei anderen Ressourcen über die Outbox mit Zusammenfassen.

### D6 – Sync

- `ResourceKind.CardioSession = 11`. Die Operationen sind `saveCardioSession` (`baseVersion` 0 legt an) und `deleteCardioSession`.
- Konflikte (`stale_base_version`, `resource_not_found`) laufen über die bestehende Fehlerzuordnung.
- Lokaler Aggregattyp ist `cardio-session`. Er wird in Codec, Typlisten, Konfliktansicht und als `forceable` eingetragen.
- Der Snapshot behält `sessionId`, weil das Modell ihn liest. `version` fällt wie üblich weg.

### D7 – Oberfläche

- **Trainings-Tab, Tagebuch:** Neben „+“ steht ein Toolbar-Button mit Herz („Cardio starten“). Cardio-Einheiten stehen im Monat zwischen den Krafttrainings. Die Zeile zeigt einen Herz-Badge, „Rad-Ergometer“, die Dauer und „Ø 132 bpm · 78 % in Zone“.
- **Start-Sheet:** Gurt (gemerkter Gurt oder „Gurt suchen“), Zielbereich von–bis (zuletzt genutzter Bereich vorbelegt, sonst 120–140), Aufwärmzeit ohne Alarm und „Starten“. Ohne Gurt lässt sich trotzdem starten, die App sagt dann, dass kein Puls erfasst wird.
- **Live-Ansicht:** großer Pulswert, darunter Status „Im Zielbereich“, „Zu hoch“ oder „Zu niedrig“ in Farbe. Dazu Zielbereich (antippbar zum Ändern), Dauer, Ø, Max, die Gurtzeile mit Akku oder „Kein Signal“ und „Beenden“.
- **Detail:** Pulskurve mit Zielband, Kennzahlen in gruppierten Karten (Dauer, Ø, Max, Zeit im Zielbereich, HRV (RMSSD)), Ergometerwerte und Notiz. Löschen ist über die Toolbar möglich.
- **Formatierung:** Zahlen sind deutsch formatiert und immer beschriftet.

## Risks

- **Swift nur in der CI:** jede Swift-Zeile vor dem Push reviewen, neue Dateien in `project.pbxproj` eintragen.
- **Gurt-Verbindung:** Ist der Gurt schon exklusiv mit einem anderen Gerät verbunden, findet die Suche ihn nicht. Die App gibt dann einen Hinweis.
- **App vom System beendet:** iOS kann die App im Hintergrund trotz BLE-Modus beenden. Der Entwurf begrenzt den Verlust auf die Werte seit dem letzten Lesen.
