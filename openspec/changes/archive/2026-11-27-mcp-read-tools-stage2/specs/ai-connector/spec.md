## MODIFIED Requirements

### Requirement: Lesende Tools

Der MCP-Server SHALL lesende Tools für Überblick, Trainings, Trainingszusammenfassung, Trainingspläne, Übungen, Cardio-Einheiten, Ziele, Check-ins, Ernährungstage, Wasser, Tagesvorlagen, Ernährungsziele, gespeicherte Gerichte, Coach-Notizen und Strava-Status anbieten, alle als nur lesend gekennzeichnet. Sie MUST ausschließlich Daten des Nutzers der verbundenen App liefern und MUST NOT Daten schreiben. Datumsbereiche MUST begrenzt sein; ein zu großer Bereich ergibt einen Tool-Fehler.

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

#### Scenario: Bereichsgrenzen
- **WHEN** `list_check_ins`, `list_workouts`, `list_cardio_sessions` oder `get_water` mehr als 366 lokale Tage abfragen
- **THEN** meldet das Tool einen Fehler statt Daten
- **AND** ohne Angabe umfassen Check-ins und Cardio-Einheiten die letzten 30 Tage, Ernährungstage und Wasser den heutigen Tag

#### Scenario: Trainingspläne
- **GIVEN** Nutzer A hat einen aktiven und einen archivierten Plan, Nutzer B einen Plan
- **WHEN** die verbundene App von Nutzer A `list_training_plans` aufruft
- **THEN** enthält die Antwort nur den aktiven Plan von A mit Einträgen in ihrer Reihenfolge (Übung mit Name, Aufwärm- und Arbeitssätze, Supersatz, Notiz)
- **AND** mit `includeArchived` auch den archivierten Plan
- **AND** `get_training_plan` mit der ID des Plans von B meldet, dass der Plan nicht gefunden wurde

#### Scenario: Cardio-Einheiten
- **GIVEN** Nutzer A hat gestern eine Einheit mit Pulsreihe aufgezeichnet
- **WHEN** die verbundene App `list_cardio_sessions` ohne Bereich aufruft
- **THEN** enthält die Antwort die Einheit mit Dauer, Durchschnitts- und Maximalpuls aus der Pulsreihe (Werte 0 ohne Signal zählen nicht), Strecke, Leistung, Energie und Notiz
- **AND** `get_cardio_session` liefert zusätzlich Pulsreihe, RR-Intervalle, Phasen und Erholungspuls

#### Scenario: Wasser
- **GIVEN** Nutzer A hat heute 1500 ml gespeichert, Nutzer B heute 999 ml
- **WHEN** die verbundene App von Nutzer A `get_water` aufruft
- **THEN** enthält die Antwort nur den heutigen Tag mit 1500 ml
- **AND** Tage ohne gespeicherten Wert fehlen; das Tagesziel liegt nur auf dem Telefon und ist nicht enthalten

#### Scenario: Tagesvorlagen
- **WHEN** die verbundene App `list_day_templates` aufruft
- **THEN** enthält die Antwort die Tagesvorlagen des Nutzers mit Tagesart, Einträgen (Mahlzeit, Produkt, Gramm, kcal und Makros) und Summen

#### Scenario: Trainingszusammenfassung
- **GIVEN** Nutzer A hat gestern zwei Trainings beendet und im zweiten das Maximalgewicht einer Übung gesteigert
- **WHEN** die verbundene App `get_workout_summary` für das zweite Training aufruft
- **THEN** enthält die Antwort Dauer, gezählte Sätze, Wiederholungen, Volumen, den besten Satz je Übung und den neuen Rekord
- **AND** die Zähler „2. Training insgesamt“ und „2. in dieser Woche“ (Montag bis Sonntag, lokale Tage)
- **AND** für ein Training von Nutzer B meldet das Tool, dass es nicht gefunden wurde

#### Scenario: Übungsfilter
- **GIVEN** Nutzer A hat eine eigene Übung ohne Muskeln in einer eigenen Kategorie und eine archivierte Übung
- **WHEN** die verbundene App `search_exercises` mit `onlyWithoutMuscles` oder der Kategorie aufruft
- **THEN** enthält die Antwort nur diese eigene Übung und einmal die Liste der Kategorien
- **AND** archivierte Übungen erscheinen nur mit `includeArchived`
- **AND** die Kategorie eines anderen Nutzers ergibt einen Tool-Fehler

#### Scenario: Trainings eines Zeitraums
- **WHEN** die verbundene App `list_workouts` mit `from` und `through` aufruft
- **THEN** enthält die Antwort nur Trainings, die an diesen lokalen Tagen begonnen haben, jeweils mit der ID des Ausgangsplans
