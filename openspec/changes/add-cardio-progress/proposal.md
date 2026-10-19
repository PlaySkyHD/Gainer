# Proposal

## Why

Cardio-Einheiten werden aufgezeichnet, aber nur einzeln angezeigt. Ob die Ausdauer besser wird, sieht der Nutzer nicht. Außerdem ist die HRV unter Belastung wenig aussagekräftig, eine Messung in Ruhe fehlt.

## What Changes

1. **Cardio-Statistik:** Im Statistik-Segment des Trainings-Tabs gibt es einen Bereich „Cardio“ mit einem Wochenziel für Minuten im Zielbereich (Standard 150 min). Er zeigt Balken der letzten 8 Wochen, Anzahl Einheiten und Gesamtdauer.
2. **Aerobe Form:** Ein Effizienzfaktor (EF = Ø-Leistung ÷ Ø-Puls) als Verlauf über die Einheiten mit eingetragener Leistung. Dazu „Ø-Puls bei gleicher Leistung“ für die häufigste Leistungsstufe (auf 10 W gerundet).
3. **Erholungspuls:** Nach „Beenden“ misst die App 60 s weiter („Erholung“, überspringbar). Gespeichert werden der Puls beim Beenden und nach 60 s. Detail und Statistik zeigen den Abfall („−28 bpm in 1 min“).
4. **HRV in Ruhe:** Eine geführte Messung mit Gurt, Standard 2 min, im Sitzen oder Liegen. Ergebnis sind Ruhepuls und RMSSD. Sie werden in den Check-in des Tages geschrieben und als Verlauf gezeigt. Der Median der letzten 7 Messungen lässt sich als Ruhepuls für die Zonen übernehmen.

### Non-Goals

- Keine automatische Messung im Hintergrund oder über Nacht.
- Keine Bewertung oder Trainingsempfehlung aus HRV (Readiness-Score) in diesem Schritt.
- Keine Leistungsmessung per Bluetooth (FTMS).

## Capabilities

- **Neu:** `cardio-progress`.

## Impact

- **Backend:**
  - `CardioSession` erhält `RecoveryStartBpm?` und `RecoveryEndBpm?`.
  - `DailyCheckIn` erhält `RestingHeartRateBpm?` und `RestingHrvMs?`.
  - Dazu je eine Migration, Validierung und Tests. Die Felder sind optional, der Vertrag bleibt rückwärtskompatibel.
- **Flutter:**
  - Statistik-Auswertung `CardioProgress`.
  - Erholungsphase im Controller und in der Live-Ansicht.
  - Screen „HRV-Messung“ und Check-in-Felder.
  - Einstellungen für das Wochenziel.
- **iOS:** keine neue Schnittstelle. Erholung und HRV-Messung nutzen `startCardioMonitoring` und `readHeartRateStatus` ohne Zonenalarm.
- **Security:** Ruhepuls und HRV sind Gesundheitsdaten im bestehenden Check-in mit Nutzerbindung.
- **Breaking Changes:** keine.
