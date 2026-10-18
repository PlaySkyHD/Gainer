# warmup-hint

## ADDED Requirements

### Requirement: Aufwärmhinweis anzeigen

Im aktiven Training SHALL jede Übung mit einem Vorwert-Gewicht für den ersten Arbeitssatz einen Aufwärmhinweis mit den gerundeten Gewichten der Aufwärmstufen zeigen. Ohne Vorwert-Gewicht, bei abgeschaltetem Hinweis oder bereits erfassten Aufwärmsätzen MUST der Hinweis fehlen. Der Hinweis MUST NOT gespeichert werden.

#### Scenario: Standardstufen
- **GIVEN** Standardstufen 50 % und 80 %, Rundung 2,5 kg und ein Vorwert von 80 kg im ersten Arbeitssatz
- **WHEN** die Übung im aktiven Training erscheint
- **THEN** zeigt sie „Aufwärmen 40 kg · 65 kg“

#### Scenario: Kein Vorwert
- **GIVEN** eine Übung ohne bisheriges Gewicht
- **WHEN** sie im aktiven Training erscheint
- **THEN** gibt es keinen Aufwärmhinweis

### Requirement: Einstellungen global und pro Übung

Der Nutzer SHALL den Hinweis global ein- und ausschalten, Standardstufen mit optionalen Wiederholungen festlegen und die Anzeige der Wiederholungen schalten können. Pro Übung SHALL er eigene Stufen und eine eigene Rundung setzen oder den Hinweis abschalten können. Standard MUST „Hinweis an, Wiederholungen aus, 50 % und 80 %, Rundung 2,5 kg“ sein.

#### Scenario: Übung abgeschaltet
- **GIVEN** der Hinweis ist global an, für „Bizepscurls“ aber aus
- **WHEN** „Bizepscurls“ im aktiven Training erscheint
- **THEN** fehlt dort der Hinweis, bei anderen Übungen bleibt er

#### Scenario: Wiederholungen anzeigen
- **GIVEN** Stufen 50 % × 8 und 80 % × 3, „Wiederholungen anzeigen“ ist an, Vorwert 100 kg
- **WHEN** die Übung erscheint
- **THEN** zeigt der Hinweis „50 kg × 8 · 80 kg × 3“

### Requirement: Als Aufwärmsätze eintragen

Ein Tipp auf den Hinweis SHALL anbieten, die Stufen als erfasste Aufwärmsätze vor dem ersten Arbeitssatz anzulegen.

#### Scenario: Eintragen
- **GIVEN** der Hinweis „40 kg · 65 kg“
- **WHEN** der Nutzer ihn antippt und „Als Aufwärmsätze eintragen“ wählt
- **THEN** stehen zwei Aufwärmsätze mit 40 kg und 65 kg vor dem ersten Arbeitssatz und der Hinweis verschwindet
