# Proposal

## Why

Krafttraining wird schon erfasst, Cardio noch gar nicht. Ein typischer Ablauf ist eine Rad-Ergometer-Einheit nach dem Krafttraining mit Pulsgurt (z. B. Polar H10). Dabei soll die App den Puls live zeigen, einen selbst gewählten Zielbereich überwachen und bei Verlassen des Bereichs warnen, auch bei gesperrtem Display. Die Einheit soll mit Pulsverlauf und HRV gespeichert und synchronisiert werden.

## What Changes

- **Cardio-Training als eigener Trainingstyp** außerhalb der Trainingspläne. Zunächst gibt es eine Sportart: „Rad-Ergometer“. Das Datenmodell ist für weitere Sportarten (später Laufen) vorbereitet.
- **Pulsgurt über Bluetooth Low Energy:** Gurt suchen und verbinden, Gerät merken, automatisch neu verbinden. Genutzt wird der Standard-Heart-Rate-Service, also Polar H10 und andere Standardgurte. Die App liest Puls, RR-Intervalle und Akkustand.
- **Zielbereich (Zone)** manuell als Pulsbereich von–bis in bpm. Er lässt sich vor dem Start und während der Einheit ändern.
- **Zonenalarm:** Ist der Puls länger als 15 s außerhalb des Bereichs, kommt eine Benachrichtigung mit Ton. Sie wiederholt sich höchstens jede Minute. Kurze Hinweise gibt es bei Rückkehr in den Bereich und bei Signalverlust. Der Alarm funktioniert auch bei gesperrtem Display.
- **Aufzeichnung und Auswertung:** Pulsverlauf in 5-Sekunden-Schritten und RR-Intervalle. Daraus berechnet die App Dauer, Ø- und Maximalpuls, Zeit im Zielbereich und HRV (RMSSD). Optional lassen sich Distanz, Ø-Leistung und kcal vom Ergometer eintragen.
- **Tagebuch:** Cardio-Einheiten erscheinen im Trainings-Tagebuch neben den Krafttrainings, mit eigener Detailansicht (Pulskurve mit Zielband, Kennzahlen, Notiz). Löschen per Wischen.
- **Sync:** neue Ressource `CardioSession` mit den Operationen `saveCardioSession` und `deleteCardioSession`.

### Non-Goals

- Keine Apple Watch und kein Wear OS als Pulsquelle, keine Android-App.
- Kein GPS und keine Lauf-Erfassung. Das Datenmodell lässt sie zu.
- Keine Zonen-Empfehlungen, keine Live Activity und kein Export nach Apple Health. Das kommt in Phase 2 als eigene Change.
- Keine Polar-spezifischen Dienste (EKG, Beschleunigung).

## Capabilities

- **Neu:** `cardio-training`.

## Impact

- **Backend:** `ResourceKind.CardioSession`, Entität `CardioSession` mit Migration (Tabelle `training.cardio_sessions`), `CardioSessionMutationHandler`, Sync-Executor, Fehlerzuordnung im Processor und Controller. Integrationstests mit zwei Nutzern.
- **API/Contracts:** keine neuen Endpunkte. Neue Operationen im bestehenden Sync-Vertrag und ein neuer Ressourcentyp im Change-Feed.
- **Flutter:** Domänenmodell und Analyse (`cardio_session.dart`), `CardioRepository`, `CardioSessionController`, Codec- und Typlisten im Sync, Screens (Start, Live, Detail) und Tagebuch.
- **iOS:** `NativeHeartRateMonitor` (CoreBluetooth), Zonenalarm-Benachrichtigungen, Pigeon-Erweiterung, `UIBackgroundModes` `bluetooth-central`, `NSBluetoothAlwaysUsageDescription`, XCTests für den Parser und die Zonenlogik.
- **Security:** Pulsdaten sind Gesundheitsdaten. Sie gehören wie alle Fitnessdaten dem Nutzer (UserId, Isolation im Backend) und landen nicht in Logs. BLE-Daten verlassen das Gerät nur über den Sync.
- **Breaking Changes:** keine. Ältere App-Versionen kennen `CardioSession` nicht. Das ist unkritisch, weil diese Ressourcen nur von einer neuen App-Version entstehen.
- **Phase:** private Kernjourney (Training).
