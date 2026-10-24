# Proposal

## Why

Ballaststoffe lassen sich in der Ernährung bisher nicht erfassen. Sie stehen auf jedem Etikett, Open Food Facts liefert sie meist mit, und die DGE nennt für Erwachsene mindestens 30 g pro Tag. Wer darauf achten will, sieht heute weder die Tagesmenge noch, wie weit er vom Richtwert entfernt ist.

## What Changes

- Einträge und Gerichtsbestandteile erhalten den optionalen Wert **Ballaststoffe in g pro 100 g**. Er wird wie Salz mit der Menge skaliert und zur Tagessumme addiert. Ohne Angabe bleibt er leer und zählt nicht mit.
- Zielphasen erhalten ein **Ballaststoffziel pro Tag** als Mindestwert. Ohne eigenen Wert gilt der DGE-Richtwert von 30 g.
- Die Tageskarte zeigt „Ballaststoffe x / y g“ mit Balken in derselben Zeile wie Salz. Anders als beim Salz ist das Ziel eine Untergrenze: Es gibt keine Warnfarbe, der Balken ist ab dem Ziel voll.
- Ballaststoffe kommen aus mehreren Quellen:
  - **Open Food Facts** bei Barcode und Suche liefert `fiber_100g`.
  - Der **Etiketten-Scan** liest Ballaststoffe ab, wenn sie gedruckt sind.
  - Die **KI-Schätzung** schätzt Ballaststoffe je Bestandteil.
  - Im **manuellen Formular** gibt es das Feld „Ballaststoffe“.
- **Durchschnitte, Kalender** und das Coach-Tool `get_nutrition_summary` zeigen Ballaststoffe.

### Non-Goals

- Kein Zucker, keine Unterarten von Ballaststoffen (löslich, unlöslich), keine Mikronährstoffe.
- Kein getrenntes Ballaststoffziel für Ruhetage; der Wert der Zielphase gilt für beide Tagesarten.
- Der Check-in übernimmt keine Ballaststoffe.
- Ballaststoffe gehen nicht in die kcal-Plausibilitätsprüfung (4/4/9) ein.

## Capabilities

- **Neu:** `fiber-tracking`.

## Einordnung

Private Kernjourney Ernährung. Grundlage für `add-bls-food-database`, das Ballaststoffe für allgemeine Lebensmittel liefert.

## Impact

- **Backend:**
  - Migration `AddFiberTracking`: nullable Spalten in `nutrition_entries`, Tagesvorlagen-Einträgen, `reusable_meal_components` und `nutrition_target_versions`, dazu Check-Constraints.
  - `NutritionPer100Grams`, `NutritionTotals`, `NutritionEntryValues`, Gerichtsbestandteile, Zielphasen und Fortschritt.
  - Sync-Payloads, Verträge und OpenAPI bekommen nur optionale Felder.
  - Open Food Facts, Etiketten-Scan (`nutrition-label-v3`) und KI-Schätzung (`meal-estimate-v5`) liefern Ballaststoffe.
  - Coach-Tool `get_nutrition_summary` gibt Ballaststoffe aus.
- **App:**
  - `NutritionTotals.fiberGrams`, Sync-Codec, API-Modelle, Zielphase.
  - Formular, Tageskarte, Zielformular, Etiketten-Prüfung, Schätzungs-Prüfung, Durchschnitte, Kalender.
- **Security:** keine Auswirkung. Es kommen nur Zahlenfelder hinzu; Nutzerbindung und Validierung folgen dem Muster von Salz.
- **Breaking Changes:** keine.
  - Der Server liest fehlende Felder als leer, alte App-Versionen funktionieren also weiter.
  - Die neue App sendet Ballaststoffe nur, wenn ein Wert gesetzt ist.
  - Die neuen Schema-Versionen von Schätzung und Etiketten-Scan ergänzen nur ein Feld; alte Apps ignorieren es.
