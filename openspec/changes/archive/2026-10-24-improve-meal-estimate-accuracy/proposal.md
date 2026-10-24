# Proposal

## Why

Die KI-Schätzung nutzte nur Modellwissen. Ein Beispiel: Hähnchenbrustfilet kam mit 8 g Fett pro 100 g heraus. Laut Nährwertdatenbanken hat es roh etwa 1–2 g, das Modell hat offenbar gebraten oder mit Haut angenommen.

## What Changes

- **Websuche:** Die Schätzung darf mit dem OpenAI-Werkzeug `web_search` Referenzwerte nachschlagen, beschränkt auf Nährwertseiten: fddb.info, naehrwertrechner.de, openfoodfacts.org und fdc.nal.usda.gov. Die Liste ist konfigurierbar, ebenso das Abschalten.
- **Prompt:** Werte pro 100 g kommen aus Nährwertdatenbanken. Grundzutaten gelten als roh, solange keine Zubereitung genannt ist. Bratfett zählt nur als eigener Bestandteil, wenn es genannt ist.
- **Quelle:** Jeder Bestandteil kann eine `sourceUrl` haben. Der Server behält sie nur als https-Link auf einer erlaubten Seite. Die App zeigt den Host im Vorschlag („… · mittel · fddb.info“) und speichert ihn als Herkunft des Eintrags („OpenAI · fddb.info“).
- **Rückfall:** Lehnt OpenAI die Suchanfrage ab (HTTP 400, z. B. ein Modell ohne Websuche), schätzt der Server einmal ohne Suche.
- **Zeit:** Das OpenAI-Zeitlimit des Servers steigt von 30 s auf 75 s, die App wartet bei der Schätzung bis zu 90 s. Das Ausgabelimit steigt von 1200 auf 2000 Token.

### Non-Goals

- Keine freie Websuche ohne Domainliste.
- Keine eigene Nährwertdatenbank-Anbindung (USDA-API), erst wenn die Websuche nicht reicht.

## Capabilities

- **Geändert:** `ai-meal-estimation`.

## Impact

- **Backend:**
  - `OpenAiMealEstimator` mit Websuche, Rückfall und Quellenprüfung.
  - `MealEstimationOptions.WebSearchEnabled` und `WebSearchDomains`.
  - Schema `meal-estimate-v3`, `MealEstimateComponentResponse.SourceUrl` (optional).
  - Zeit- und Tokenlimit in Optionen, `compose.yaml` und `.env.example`.
  - `THIRD_PARTY_POLICY.md`.
- **App:** API-Modell, `NutritionEstimateComponent.sourceUrl`, Vorschlagszeile, Herkunft des Eintrags, eigenes Empfangs-Zeitlimit für die Schätzung.
- **Kosten:** pro Schätzung zusätzlich die Kosten der Suchaufrufe.
