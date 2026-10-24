# Design

## Decisions

### D1 – Cardio-Statistik

- **Woche:** Montag bis Sonntag in lokaler Zeit.
- **Minuten im Ziel:** Summe von `timeInZone` (Zielbereich der jeweiligen Einheit).
  - Sind Zonen konfiguriert, zeigt ein Umschalter zusätzlich „Zone 2“. Gemeint ist die Zeit mit Puls in Zone 2 der aktuellen Einstellungen, rückwirkend aus den gespeicherten Reihen berechnet.
- **Wochenziel:** in `CardioPreferences.weeklyTargetMinutes`, Standard 150, Bereich 30–600.
- **Darstellung:** 8 Balken mit Ziellinie, darunter „Diese Woche 95 / 150 min · 3 Einheiten · 1:42 h“.
- **Berechnung:** rein in Dart (`CardioProgress`) aus den lokalen Einheiten, offline verfügbar. Wie bei `CardioAnalysis` ist das eine bewusste Ausnahme von „Analytics im Backend“.

### D2 – Aerobe Form

- **EF je Einheit:** `averagePowerWatts / averageBpm`, auf zwei Nachkommastellen gerundet, nur wenn beides vorhanden ist.
- **Verlauf:** Linie der letzten 20 Einheiten mit EF.
- **Vergleich bei gleicher Leistung:** Die häufigste Leistungsstufe (`round(W / 10) × 10`) ab 3 Einheiten. Gezeigt werden erster und letzter Ø-Puls dieser Stufe: „bei 150 W: 138 → 131 bpm“.
- **Hinweis:** Ohne eingetragene Leistung erscheint „Trage die Ø-Leistung vom Ergometer ein, um deine Form zu sehen.“

### D3 – Erholungspuls

- **Ablauf:** „Beenden“ legt `endedAtUtc` fest und speichert die Einheit sofort, Dauer und Kennzahlen enden dort.
  - Danach zeigt die Live-Ansicht „Erholung 0:60“ mit Countdown und Puls. Die native Überwachung läuft ohne Alarm weiter (`alertsEnabled=false`, keine Zone).
- **Werte:**
  - `recoveryStartBpm` ist der Mittelwert der letzten 10 s vor dem Beenden.
  - `recoveryEndBpm` ist der Mittelwert der Werte 55–65 s nach dem Beenden.
  - Nach Ende der Erholung werden beide als `update` der Einheit gespeichert.
- **Abbruch:** „Überspringen“, kein Signal oder App-Wechsel lassen die Felder leer.
- **Backend-Validierung:** 25–250, beide oder keiner.
- **Anzeige:** „Erholung −28 bpm in 1 min“ im Detail. In der Statistik der Mittelwert der letzten 5 Einheiten.

### D4 – HRV in Ruhe

- **Einstieg:** Screen „HRV-Messung“ aus dem Check-in (Körper-Tab) und aus den Cardio-Einstellungen.
  - Voraussetzung ist ein verbundener Gurt. Ohne Gurt ist der Button deaktiviert, mit Begründung.
- **Ablauf:**
  - 30 s Einschwingen werden nicht gewertet, danach die Messdauer (1–5 min, Standard 2).
  - Angezeigt werden ein Countdown, der Live-Puls und die Zahl gültiger RR-Werte.
  - Technisch eine Überwachung mit eigener `sessionId`, ohne Alarm und ohne Live Activity. Es wird keine `CardioSession` gespeichert.
- **Ergebnis:**
  - RMSSD nach der Regel aus `CardioAnalysis` (Artefaktfilter, mindestens 30 Differenzen).
  - Ruhepuls ist der Median der bpm-Werte.
  - Liegt der Artefaktanteil über 20 %, erscheint „Messung unruhig – wiederholen?“ mit der Wahl „Trotzdem speichern“ oder „Wiederholen“.
- **Speicherung:** in den Check-in des Tages (`restingHeartRateBpm` 25–150, `restingHrvMs` 1–300). Fehlt der Check-in, wird er wie beim Health-Import angelegt bzw. ergänzt. Der Check-in verlangt Gewicht: Fehlt das Gewicht, speichert die App lokal einen „wartenden Wert“ und schreibt ihn beim nächsten Check-in mit. Das Verhalten folgt dem bestehenden Check-in-Modell und wird dort geprüft.
- **Verlauf:** Liniendiagramm von HRV und Ruhepuls (30 Tage) im Körper-Tab.
- **Zonen:** „Als Ruhepuls übernehmen“ setzt `CardioPreferences.restingHeartRate` auf den Median der letzten 7 Messungen.
