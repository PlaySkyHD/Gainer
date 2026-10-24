# duplicate-plan

## ADDED Requirements

### Requirement: Plan duplizieren

Langes Drücken auf einen Plan in der Planliste SHALL ein Kontext-Sheet mit „Duplizieren“ öffnen. Duplizieren SHALL einen neuen Plan „<Name> Kopie“ am Ende der Liste anlegen, der Einträge, Sätze, Notizen, Supersets und Vorwerte-Quelle übernimmt, und ihn im Planeditor öffnen. Plan, Einträge und Supersets MUST neue IDs bekommen.

#### Scenario: Kopie anlegen
- **GIVEN** die Pläne „Push“ und „Pull“, „Pull“ mit einem Superset aus Latzug und Rudern
- **WHEN** der Nutzer lange auf „Pull“ drückt und „Duplizieren“ wählt
- **THEN** stehen „Push“, „Pull“ und „Pull Kopie“ in der Liste, der Planeditor zeigt „Pull Kopie“, und die Kopie enthält Latzug und Rudern als Superset mit neuer Superset-ID

#### Scenario: Langer Name
- **GIVEN** ein Plan mit 160 Zeichen langem Namen
- **WHEN** er dupliziert wird
- **THEN** ist der neue Name 160 Zeichen lang und endet auf „ Kopie“
