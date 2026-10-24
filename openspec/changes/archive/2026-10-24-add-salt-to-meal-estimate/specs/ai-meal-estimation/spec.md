# ai-meal-estimation

## ADDED Requirements

### Requirement: Salz in der Mahlzeiten-Schätzung

Die KI-Schätzung SHALL Salz je Bestandteil nur angeben, wenn es von Haus aus im Essen steckt (z. B. Brot, Käse, Pizza, Döner). Für schlichte oder selbstgekochte Zutaten MUST sie kein Salz angeben, und Salz, das beim Kochen dazukommt, MUST NOT geschätzt werden. Nennt die Beschreibung eine Salzmenge, SHALL daraus ein eigener Bestandteil „Salz“ mit 0 kcal werden.

#### Scenario: Pizza
- **GIVEN** die Beschreibung „Pizza Margherita“
- **WHEN** die KI schätzt
- **THEN** zeigt der Vorschlag z. B. „350 g · 890 kcal · ~3,5 g Salz · mittel“

#### Scenario: Selbst gekocht und gesalzen
- **GIVEN** die Beschreibung „Hähnchen mit Reis, selbst gesalzen“
- **WHEN** die KI schätzt
- **THEN** haben Hähnchen und Reis kein Salz, und der Vorschlag bietet „Selbst gesalzen? Salz hinzufügen“ an

#### Scenario: Genannte Menge
- **GIVEN** die Beschreibung „Reis mit einem Teelöffel Salz“
- **WHEN** die KI schätzt
- **THEN** enthält der Vorschlag den Bestandteil „Salz“ mit 6 g und 0 kcal

### Requirement: Bestandteile einzeln übernehmen

Übernimmt der Nutzer einen Bestandteil, SHALL nur dieser aus dem Vorschlag verschwinden. Die übrigen MUST zum Prüfen stehen bleiben.

#### Scenario: Zwei Bestandteile
- **GIVEN** ein Vorschlag mit „Pizza Margherita“ und „Reis“
- **WHEN** der Nutzer „Pizza Margherita“ übernimmt
- **THEN** steht „Reis“ weiterhin im Vorschlag
