## MODIFIED Requirements

### Requirement: Deterministische Übungsentwicklung

Das System MUST pro Übung und Zeitraum den besten Satz, verwendetes Gewicht, Wiederholungen, Gesamtvolumen, Anzahl abgeschlossener Trainings und geschätztes 1RM ausschließlich aus abgeschlossenen eigenen Sätzen berechnen. Die Formel für das geschätzte 1RM SHALL dokumentiert und versioniert sein; nicht geeignete Sätze müssen als nicht berechenbar behandelt werden.

#### Scenario: Übungsfortschritt berechnen

- **GIVEN** ein Nutzer besitzt mehrere abgeschlossene Trainings derselben stabilen Übungs-ID im gewählten Zeitraum
- **WHEN** er den Übungsfortschritt abruft
- **THEN** werden die Kennzahlen reproduzierbar aus genau diesen Sätzen berechnet und mit Zeitraum sowie Berechnungsversion ausgegeben

#### Scenario: Laufendes Workout ausschließen

- **GIVEN** ein Nutzer besitzt ein abgeschlossenes und ein noch laufendes Training derselben Übung
- **WHEN** der Fortschritt berechnet wird
- **THEN** fließen ausschließlich Sätze des abgeschlossenen Trainings ein

#### Scenario: Fremde oder ungeeignete Sätze ausschließen

- **GIVEN** es existieren Sätze anderer Nutzer oder Sätze ohne für das geschätzte 1RM geeignete Werte
- **WHEN** die Kennzahlen des authentifizierten Nutzers berechnet werden
- **THEN** fließen fremde Sätze nie ein und ungeeignete Sätze erzeugen keinen geschätzten 1RM-Wert
