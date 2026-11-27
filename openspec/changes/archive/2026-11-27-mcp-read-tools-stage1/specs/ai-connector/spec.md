## MODIFIED Requirements

### Requirement: Lesende Tools

Der MCP-Server SHALL lesende Tools für Überblick, Trainings, Übungen, Ziele, Check-ins, Ernährungstage, Ernährungsziele, gespeicherte Gerichte, Coach-Notizen und Strava-Status anbieten, alle als nur lesend gekennzeichnet. Sie MUST ausschließlich Daten des Nutzers der verbundenen App liefern und MUST NOT Daten schreiben. Datumsbereiche MUST begrenzt sein (Check-ins höchstens 366 Tage, Ernährungstage höchstens 31 Tage); ein zu großer Bereich ergibt einen Tool-Fehler.

#### Scenario: Fremdes Training
- **GIVEN** Nutzer B besitzt ein Training
- **WHEN** die verbundene App von Nutzer A `get_workout` mit dessen ID aufruft
- **THEN** meldet das Tool, dass das Training nicht gefunden wurde

#### Scenario: Überblick
- **GIVEN** Nutzer A hat in den letzten 30 Tagen trainiert und gewogen
- **WHEN** die verbundene App `get_overview` mit 30 Tagen aufruft
- **THEN** enthält die Antwort Trainingsanzahl, Volumen, Gewichtsdurchschnitt, Gewichtsreihe und Ernährungsdurchschnitte dieses Zeitraums

#### Scenario: Check-ins eines Monats
- **GIVEN** Nutzer A hat am 19. November gewogen, Nutzer B am 20. November
- **WHEN** die verbundene App von Nutzer A `list_check_ins` für November aufruft
- **THEN** enthält die Antwort nur den Check-in vom 19. November mit Gewicht und HRV

#### Scenario: Zu großer Bereich
- **WHEN** `get_nutrition_days` mehr als 31 Tage abfragt
- **THEN** meldet das Tool einen Fehler statt Daten
