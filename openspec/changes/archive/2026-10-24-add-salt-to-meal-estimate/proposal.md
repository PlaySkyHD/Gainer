# Proposal

## Why

Mit dem Salz-Tracking (`add-salt-tracking`) fehlt Salz noch in der KI-Schätzung. Selbstgekochtes Essen darf die KI dabei nicht pauschal salzen, sonst ist der Tageswert falsch, und eigenes Salz („Salz hinzufügen“) würde doppelt zählen.

## What Changes

- Jeder geschätzte Bestandteil hat optional `saltGrams`. Die KI füllt es nur für Salz, das von Haus aus im Essen steckt: Brot, Käse, Wurst, Soßen, Fertiggerichte, Pizza, Döner, Restaurantessen. Bei Grundzutaten wie Reis, Nudeln, Gemüse oder frischem Fleisch bleibt es leer. Salz, das beim Kochen dazukommt, schätzt sie nie.
- Nennt die Beschreibung eine Menge („mit einem Teelöffel Salz“), wird daraus ein eigener Bestandteil „Salz“ mit 0 kcal.
- Der Vorschlag zeigt den Wert als „~1,1 g Salz“, die Sicherheit auf Deutsch („unsicher“, „mittel“, „sicher“) und darunter „Selbst gesalzen? Salz hinzufügen“ mit direktem Sprung zur Salz-Schnellwahl.
- Übernimmt man einen Bestandteil, verschwindet nur dieser aus dem Vorschlag, die übrigen bleiben stehen. Bisher wurde der ganze Vorschlag verworfen.

### Non-Goals

- Keine Schätzung von Salz, das beim Kochen dazukommt.

## Capabilities

- **Geändert:** `ai-meal-estimation`.

## Impact

- Backend: `MealEstimateComponentDraft.SaltGrams`, Schema `meal-estimate-v2`, optionales Feld in `MealEstimateComponentResponse`; 0 kcal für einen Bestandteil erlaubt.
- App: API-Modell, Vorschlagszeile, Hinweis, Teilübernahme.
