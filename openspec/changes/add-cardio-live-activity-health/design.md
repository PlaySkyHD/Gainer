# Design

## Decisions

### D1 – Live Activity

- **Attribute:** `GainerCardioActivityAttributes` mit `sessionId`, `title` und `startedAt`. Der `ContentState` enthält `bpm?`, `zoneLowBpm?`, `zoneHighBpm?`, `zoneState` (`inZone`, `above`, `below`, `noSignal`, `none`) und `updatedAt`.
- **Steuerung in Swift:** Die Activity startet mit `startCardioMonitoring`, wenn `liveActivityEnabled` gesetzt und Live Activities erlaubt sind. Sie endet mit `stopCardioMonitoring`.
- **Aktualisierung:** bei Wechsel des Zonenstatus sofort, sonst höchstens alle 5 s und nur bei geändertem Puls. So bleibt das ActivityKit-Budget geschont.
- **Darstellung:**
  - **Sperrbildschirm:** großer Puls mit Herz, Status in Zonenfarbe, „Ziel 125–140“ und Dauer als `Text(timerInterval:)`.
  - **Dynamic Island:** kompakt Herz plus bpm, minimal ein Herz in Zonenfarbe.
- **Antippen:** öffnet die Route `training` mit Quelle `liveActivity`. Ist eine Cardio-Einheit aktiv, öffnet die App die Live-Ansicht.

### D2 – Apple Health

- **Pigeon:** `requestCardioWriteAuthorization()` fragt Schreiben für Workout, `heartRate`, `distanceCycling` und `activeEnergyBurned` an. `exportCardioSession(PlatformCardioExport)` schreibt die Einheit.
- **Workout:** `HKWorkout` mit `.cycling` und `HKMetadataKeyIndoorWorkout = true`.
- **Pulsproben:** eine `heartRate`-Probe je Wert > 0, Zeitpunkt Start + Index × Intervall.
- **Werte:** Distanz und Energie nur, wenn sie eingetragen sind.
- **Dubletten:** `HKMetadataKeySyncIdentifier` ist `gainer.cardio.<accountId>.<sessionId>`, `HKMetadataKeySyncVersion` ist die lokale Version. Bei gleicher oder höherer vorhandener Version kommt `alreadyPresent`.
- **Ledger:** Dart merkt den Export in den Sync-Metadaten (`health-ledger:cardio-export:<id>`). Die Detailansicht zeigt dann „In Apple Health gesichert“.

### D3 – Zonen

- **Einstellungen:** `CardioPreferences` liegt lokal pro Konto in den Trainingseinstellungen: `maxHeartRate?`, `age?`, `restingHeartRate?`, `lastZoneLow`, `lastZoneHigh`, `warmupSeconds`.
- **Maximalpuls:** angegebener Wert, sonst `round(208 − 0,7 × Alter)`, sonst keine Empfehlung.
- **Grenzen in % von HFmax:** Z1 50–60, Z2 60–70, Z3 70–80, Z4 80–90, Z5 90–100.
- **Mit Ruhepuls (Karvonen):** Grenze = Ruhepuls + % × (HFmax − Ruhepuls).
- **Rundung:** auf ganze bpm. Die untere Grenze ist inklusiv, die obere Grenze einer Zone ist die untere der nächsten.
- **Beispiel ohne Ruhepuls:** HFmax 190 ergibt Zone 2 = 114–133.
- **Beispiel mit Ruhepuls:** HFmax 190 und Ruhepuls 60 ergeben Zone 2 = 138–151.
