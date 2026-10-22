# piece-counts

## ADDED Requirements

### Requirement: Menge in Stück

Der Nutzer SHALL die Menge eines Lebensmittels mit bekanntem Stückgewicht als Anzahl eingeben können. Die App SHALL die Grammzahl als Anzahl × Stückgewicht berechnen und den Eintrag in der Liste mit der Anzahl anzeigen. Ein Stückgewicht SHALL aus Open Food Facts, der KI-Schätzung, der manuellen Eingabe oder einem früheren Eintrag stammen können.

#### Scenario: Vier Eier
- **GIVEN** „Ei, gekocht“ mit 50 g pro Stück in „Zuletzt verwendet“
- **WHEN** der Nutzer bei „Anzahl“ 4 wählt und das Ei antippt
- **THEN** entsteht ein Eintrag mit 200 g, und die Liste zeigt „4 Stk · 310 kcal“

#### Scenario: Manuell mit Stückgewicht
- **GIVEN** das manuelle Formular
- **WHEN** der Nutzer „Gewicht pro Stück“ 50 g und „Anzahl“ 4 eingibt
- **THEN** steht bei „Menge“ 200 g, und beim nächsten Mal kennt „Zuletzt verwendet“ das Stückgewicht

#### Scenario: Kein Stückgewicht bekannt
- **GIVEN** ein Lebensmittel ohne Stückgewicht
- **WHEN** der Nutzer eine Anzahl wählt und es antippt
- **THEN** zeigt die App „Für … ist kein Stückgewicht bekannt. Gib die Menge in g ein.“ und speichert nichts

### Requirement: Stückzahl passt zur Menge

Server und App MUST einen Eintrag ablehnen, dessen Grammzahl nicht Stückzahl × Stückgewicht entspricht, und eine Stückzahl ohne Stückgewicht. Bei der KI-Schätzung SHALL eine unpassende Stückangabe verworfen werden, die Schätzung in Gramm bleibt erhalten.

#### Scenario: KI zählt Eier
- **GIVEN** die Beschreibung „4 Eier“
- **WHEN** die KI 4 Stück zu je 55 g und 220 g liefert
- **THEN** zeigt der Vorschlag „4 Stk · 220 g · …“
