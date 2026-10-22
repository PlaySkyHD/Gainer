# Proposal

## Why

Salz lässt sich in der Ernährung bisher nicht erfassen. Wer auf seinen Salzkonsum achten will, sieht weder die Tagesmenge noch eine Obergrenze.

## What Changes

- Einträge und Gerichtsbestandteile erhalten den optionalen Wert **Salz in g pro 100 g**. Er wird wie die Makros mit der Menge skaliert und zur Tagessumme addiert. Ohne Angabe bleibt er leer und zählt nicht mit.
- Zielphasen erhalten eine **Salzobergrenze pro Tag**. Ohne eigenen Wert gilt der Richtwert von 6 g, den die DGE nennt.
- Die Tageskarte zeigt „Salz x / y g“ mit Balken; ab der Grenze erscheint der Balken in Warnfarbe.
- Salz kommt aus mehreren Quellen:
  - **Open Food Facts** bei Barcode und Suche liefert `salt_100g`, ersatzweise Natrium × 2,5.
  - Beim **Etiketten-Scan** liest das Modell Salz oder Natrium ab, der Server rechnet Natrium in Salz um.
  - Im **manuellen Formular** gibt es das Feld „Salz“.
- **Durchschnitte und Kalender** zeigen Salz.

### Non-Goals

- Die KI-Schätzung von Mahlzeiten schätzt kein Salz.
- Natrium wird nicht als eigener Wert geführt, sondern immer in Salz umgerechnet.
- Der Check-in übernimmt kein Salz.

## Capabilities

- **Neu:** `salt-tracking`.

## Impact

- **Backend:**
  - Migration `AddSaltTracking`: nullable Spalten in `nutrition_entries`, `reusable_meal_components` und `nutrition_target_versions`, dazu Check-Constraints.
  - Sync-Payloads, Verträge und OpenAPI bekommen nur optionale Felder.
  - Open Food Facts und Etiketten-Scan (`nutrition-label-v2`) liefern Salz.
- **App:**
  - `NutritionTotals.saltGrams`, Sync-Codec, API-Modelle
  - Formular, Tageskarte, Zielphase, Etiketten-Prüfung, Durchschnitte, Kalender
- **Kompatibilität:**
  - Der Server liest fehlende Felder als leer, alte App-Versionen funktionieren also weiter.
  - Die neue App sendet Salz nur, wenn ein Wert gesetzt ist.
