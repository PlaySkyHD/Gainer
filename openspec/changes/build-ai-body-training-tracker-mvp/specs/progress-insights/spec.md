## Purpose

Diese Capability liefert nachvollziehbare, serverseitig deterministisch berechnete Fortschrittswerte für Gewicht, Ernährung und Trainingsleistung, ohne fehlende Daten zu erfinden.

## ADDED Requirements

### Requirement: Gewichtsübersicht und Zeiträume

Das System MUST das aktuellste Gewicht, den arithmetischen 7-Tage-Durchschnitt und eine Gewichtsänderung in Kilogramm pro Woche aus den eigenen Check-ins berechnen. Es SHALL Gewichtsreihen für `7 Tage`, `30 Tage`, `90 Tage` und `Gesamt` bereitstellen und Tage ohne Eintrag nicht als Gewicht null behandeln.

#### Scenario: 7-Tage-Durchschnitt berechnen

- **GIVEN** ein Nutzer besitzt in den letzten sieben lokalen Kalendertagen fünf Gewichtseinträge
- **WHEN** die Gewichtsübersicht berechnet wird
- **THEN** entspricht der 7-Tage-Durchschnitt dem arithmetischen Mittel genau dieser fünf Werte und die Datenabdeckung wird als fünf von sieben Tagen ausgewiesen

#### Scenario: Zeitraum auswählen

- **GIVEN** ein Nutzer besitzt Gewichtseinträge über mehr als 90 Tage
- **WHEN** er den Zeitraum `30 Tage` auswählt
- **THEN** enthält die Zeitreihe ausschließlich seine Einträge im definierten 30-Tage-Fenster in chronologischer Reihenfolge

### Requirement: Gewichtstrend mit ausreichender Datengrundlage

Das System SHALL die Gewichtsänderung pro Woche anhand einer dokumentierten, versionierten und für identische Eingaben reproduzierbaren Trendberechnung bestimmen. Es MUST bei weniger als drei Gewichtseinträgen im betrachteten Zeitraum statt eines Trends den Zustand `unzureichende Daten` liefern.

#### Scenario: Reproduzierbarer Trend

- **GIVEN** dieselben datierten Gewichtseinträge und dieselbe Berechnungsversion
- **WHEN** der Trend mehrfach oder für verschiedene Clients berechnet wird
- **THEN** sind Ergebnis, Einheit, Zeitraum und Berechnungsversion identisch

#### Scenario: Zu wenige Gewichtseinträge

- **GIVEN** im gewählten Zeitraum existieren nur zwei Gewichtseinträge
- **WHEN** der Gewichtstrend angefordert wird
- **THEN** liefert das System keinen numerischen Wochenwert und kennzeichnet die Datengrundlage als unzureichend

### Requirement: Ernährungs- und Aktivitätskennzahlen

Das System MUST für ausgewählte Zeiträume Durchschnittswerte für Kalorien, Protein, Kohlenhydrate, Fett, Schritte und Schlaf ausschließlich über Tage berechnen, an denen der jeweilige Wert erfasst wurde. Fehlende Werte dürfen nicht als null einfließen; zu jedem Wert SHALL die Anzahl berücksichtigter Tage ausgegeben werden.

#### Scenario: Teilweise erfasste Ernährung

- **GIVEN** ein Nutzer hat in sieben Tagen an fünf Tagen Kalorien und an drei Tagen Protein erfasst
- **WHEN** die 7-Tage-Kennzahlen berechnet werden
- **THEN** verwendet der Kaloriendurchschnitt fünf und der Proteindurchschnitt drei Werte und weist beide Abdeckungen getrennt aus

#### Scenario: Keine Werte für eine Kennzahl

- **GIVEN** im Zeitraum wurde kein Fettwert erfasst
- **WHEN** die Ernährungskennzahlen berechnet werden
- **THEN** liefert das System für Fett `keine Daten` statt eines Durchschnitts von null

### Requirement: Deterministische Übungsentwicklung

Das System MUST pro Übung und Zeitraum Best Set, verwendetes Gewicht, Wiederholungen, Gesamtvolumen, Anzahl abgeschlossener Workouts und Estimated 1RM ausschließlich aus abgeschlossenen eigenen Sätzen berechnen. Die Estimated-1RM-Formel SHALL dokumentiert und versioniert sein; nicht geeignete Sätze müssen als nicht berechenbar behandelt werden.

#### Scenario: Übungsfortschritt berechnen

- **GIVEN** ein Nutzer besitzt mehrere abgeschlossene Workouts derselben stabilen Übungs-ID im gewählten Zeitraum
- **WHEN** er den Übungsfortschritt abruft
- **THEN** werden die Kennzahlen reproduzierbar aus genau diesen Sätzen berechnet und mit Zeitraum sowie Berechnungsversion ausgegeben

#### Scenario: Laufendes Workout ausschließen

- **GIVEN** ein Nutzer besitzt ein abgeschlossenes und ein noch laufendes Workout derselben Übung
- **WHEN** der Fortschritt berechnet wird
- **THEN** fließen ausschließlich Sätze des abgeschlossenen Workouts ein

#### Scenario: Fremde oder ungeeignete Sätze ausschließen

- **GIVEN** es existieren Sätze anderer Nutzer oder Sätze ohne für Estimated 1RM geeignete Werte
- **WHEN** die Kennzahlen des authentifizierten Nutzers berechnet werden
- **THEN** fließen fremde Sätze nie ein und ungeeignete Sätze erzeugen keinen geschätzten 1RM-Wert

### Requirement: Dashboard-Zusammenfassung

Das System SHALL für den authentifizierten Nutzer eine Übersicht aus aktivem Ziel, aktuellstem Gewicht, 7-Tage-Gewichtsdurchschnitt, Gewichtstrend, durchschnittlichen Kalorien und Protein sowie Anzahl abgeschlossener Workouts der aktuellen lokalen Kalenderwoche bereitstellen.

#### Scenario: Vollständige Dashboard-Daten

- **GIVEN** ein Nutzer besitzt ein aktives Ziel sowie ausreichende Gewichts-, Ernährungs- und Workout-Daten
- **WHEN** er das Dashboard öffnet
- **THEN** zeigt die Übersicht ausschließlich seine deterministisch berechneten Kennzahlen mit den zugehörigen Zeiträumen

#### Scenario: Teilweise fehlende Dashboard-Daten

- **GIVEN** ein Nutzer besitzt ein Ziel und Gewichtseinträge, aber keine Ernährungs- oder Workout-Daten
- **WHEN** er das Dashboard öffnet
- **THEN** bleiben die verfügbaren Kennzahlen sichtbar und die fehlenden Bereiche werden jeweils als `keine Daten` gekennzeichnet

### Requirement: Analytics bleiben unabhängig von der KI

Das System MUST alle numerischen Fortschrittskennzahlen ohne Beteiligung eines Sprachmodells berechnen und SHALL sie über denselben nutzergebundenen Vertrag an UI und AI Coach liefern.

#### Scenario: OpenAI ist nicht erreichbar

- **GIVEN** der externe KI-Dienst ist nicht verfügbar
- **WHEN** der Nutzer Dashboard oder Übungsfortschritt abruft
- **THEN** werden alle deterministischen Kennzahlen weiterhin vollständig bereitgestellt

#### Scenario: UI und AI verwenden dieselbe Kennzahl

- **GIVEN** UI und AI Coach fragen dieselbe Kennzahl für denselben Nutzer, Zeitraum und Datenstand ab
- **WHEN** das Backend beide Anfragen verarbeitet
- **THEN** erhalten beide denselben Wert und dieselbe Berechnungsversion
