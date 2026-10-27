## MODIFIED Requirements

### Requirement: Aufwärmhinweis anzeigen

Im aktiven Training SHALL jede Übung mit einem Vorwert-Gewicht für den ersten Arbeitssatz einen Aufwärmhinweis mit den gerundeten Gewichten der Aufwärmstufen zeigen. Ohne Vorwert-Gewicht, bei abgeschaltetem Hinweis oder bereits erfassten Aufwärmsätzen MUST der Hinweis fehlen. Bei assistierten Übungen MUST der Hinweis immer fehlen, weil das Gewicht dort die Unterstützung ist und Aufwärmstufen schwerer als der Arbeitssatz wären. Der Hinweis MUST NOT gespeichert werden.

#### Scenario: Standardstufen
- **GIVEN** Standardstufen 50 % und 80 %, Rundung 2,5 kg und ein Vorwert von 80 kg im ersten Arbeitssatz
- **WHEN** die Übung im aktiven Training erscheint
- **THEN** zeigt sie „Aufwärmen 40 kg · 65 kg“

#### Scenario: Kein Vorwert
- **GIVEN** eine Übung ohne bisheriges Gewicht
- **WHEN** sie im aktiven Training erscheint
- **THEN** gibt es keinen Aufwärmhinweis

#### Scenario: Assistierte Übung
- **GIVEN** eine assistierte Übung mit einem Vorwert von 40 kg Unterstützung
- **WHEN** sie im aktiven Training erscheint
- **THEN** gibt es keinen Aufwärmhinweis und kein „Als Aufwärmsätze eintragen“
