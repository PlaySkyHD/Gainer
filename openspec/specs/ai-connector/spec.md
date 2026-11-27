# ai-connector Specification

## Purpose
Externe KI-Assistenten wie ChatGPT lesen die Daten eines Nutzers über einen MCP-Server, nachdem der Nutzer sie per OAuth und Passkey freigegeben hat. Der Zugriff ist auf lesende Tools und die eigenen Daten begrenzt.

## Requirements

### Requirement: MCP-Endpunkt für KI-Assistenten

Die API SHALL unter `/api/v1/mcp` einen MCP-Server über Streamable HTTP anbieten. Er MUST nur Anfragen mit dem Token einer verbundenen App annehmen. Ohne gültiges Token MUST er 401 mit `WWW-Authenticate: Bearer resource_metadata="…"` antworten, mit dem App-Token einer Geräte-Session 403.

#### Scenario: Ohne Token
- **GIVEN** ChatGPT kennt nur die URL des MCP-Servers
- **WHEN** es `/api/v1/mcp` ohne Token aufruft
- **THEN** antwortet die API mit 401 und verweist im Header auf die Protected-Resource-Metadaten

#### Scenario: App-Token
- **GIVEN** ein Access-Token der iOS-App
- **WHEN** damit `/api/v1/mcp` aufgerufen wird
- **THEN** antwortet die API mit 403

### Requirement: Lesende Tools

Der MCP-Server SHALL lesende Tools für Überblick, Trainings mit Zusammenfassung, Verlauf, Trainingstagen und Muskelvolumen, Pläne, Übungen, Cardio mit Kennzahlen, Ziele, Check-ins, Ernährung mit Durchschnitt, Wasser, Vorlagen, Ernährungsziele, Gerichte, Coach-Notizen und Strava anbieten, alle nur lesend. Sie MUST ausschließlich Daten des Nutzers der verbundenen App liefern und MUST NOT Daten schreiben. Datumsbereiche MUST begrenzt sein; ein zu großer Bereich ergibt einen Tool-Fehler.

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

#### Scenario: Trainingsverlauf
- **GIVEN** Nutzer A hat gestern und vor zehn Tagen trainiert, Nutzer B gestern
- **WHEN** die verbundene App von Nutzer A `get_training_trends` mit `fourWeeks` aufruft
- **THEN** enthält die Antwort zwei Trainings mit Sätzen, Wiederholungen, Volumen, Dauer und jüngstem Körpergewicht von A sowie vier Wochenabschnitte
- **AND** Abschnitte ohne Training enthalten keine Durchschnitte, und mit `includeWarmups` zählen Aufwärmsätze mit
- **AND** ein unbekannter Zeitraum ergibt einen Tool-Fehler

#### Scenario: Trainingstage
- **GIVEN** Nutzer A hat gestern 60 Minuten Kraft und 30 Minuten Cardio trainiert und vor zehn Tagen 60 Minuten Kraft
- **WHEN** die verbundene App `get_training_heatmap` aufruft
- **THEN** enthält die Antwort genau diese zwei Tage mit 90 und 60 Minuten, die Quartilsgrenzen und die Stufen 4 und 1

#### Scenario: Muskelvolumen
- **GIVEN** Nutzer A hat einen aktiven Plan mit 4 Arbeitssätzen einer Brustübung mit Trizeps als Hilfsmuskel und einen archivierten Plan
- **WHEN** die verbundene App `get_muscle_volume` ohne Argumente aufruft
- **THEN** enthält die Antwort alle 17 Muskeln, zuerst Brust mit 4 Sätzen (Stufe medium) und Trizeps mit 2, sowie die Übungen ohne Muskeln
- **AND** `trained` zählt die erfassten Arbeitssätze der letzten 7 Tage oder je Woche der letzten 28 Tage
- **AND** der Plan von Nutzer B, eine unbekannte Quelle oder ein Plan bei `trained` ergeben einen Tool-Fehler

#### Scenario: Kennzahlen einer Cardio-Einheit
- **GIVEN** eine Einheit von Nutzer A mit Zielbereich, Pulsreihe und Erholungspuls
- **WHEN** die verbundene App `get_cardio_session` aufruft
- **THEN** enthalten die Kennzahlen Dauer, Durchschnittspuls, Zeit und Anteil im Zielbereich und die Erholung wie in der App
- **AND** die HRV fehlt bei weniger als 30 gültigen RR-Differenzen; Pulszonen, Wochenziel und Maximalpuls liegen nur auf dem Telefon

#### Scenario: Ernährungsdurchschnitt
- **GIVEN** Nutzer A hat heute nichts und an drei der letzten sieben Tage gegessen, einer davon als Ruhetag festgelegt
- **WHEN** die verbundene App `get_nutrition_averages` mit 7 Tagen aufruft
- **THEN** endet das Fenster gestern und enthält Durchschnitte je erfasstem Tag, „2 von 3 Tagen im Zielbereich“ mit dem Ruhetag-Ziel für den Ruhetag und die kcal je Tag
- **AND** Daten von Nutzer B fehlen, und andere Fensterlängen als 7 oder 30 ergeben einen Tool-Fehler

### Requirement: OAuth-Discovery

Die API SHALL Protected-Resource-Metadaten unter `/.well-known/oauth-protected-resource` und `/.well-known/oauth-protected-resource/api/v1/mcp` sowie Authorization-Server-Metadaten unter `/.well-known/oauth-authorization-server` ausliefern. Die Metadaten MUST `code` als Antworttyp, `authorization_code` und `refresh_token` als Grant, `S256` als einzige PKCE-Methode und `none` als Client-Authentifizierung nennen.

#### Scenario: Discovery
- **GIVEN** ChatGPT hat einen 401 mit `resource_metadata` erhalten
- **WHEN** es die Metadaten abruft
- **THEN** findet es Autorisierungs-, Token- und Registrierungsendpunkt und die unterstützte PKCE-Methode

### Requirement: Client-Registrierung

`POST /api/v1/oauth/register` SHALL öffentliche Clients ohne Speicherung registrieren. Jede Redirect-URI MUST HTTPS verwenden und auf einem erlaubten Host liegen; sonst MUST die Registrierung mit `invalid_redirect_uri` scheitern. Der Endpunkt MUST pro Client begrenzt sein.

#### Scenario: Fremder Host
- **GIVEN** eine Registrierung mit `https://attacker.example/callback`
- **WHEN** sie eintrifft
- **THEN** antwortet die API mit 400 und `invalid_redirect_uri`

### Requirement: Freigabe mit Passkey

`GET /api/v1/oauth/authorize` SHALL eine Freigabeseite zeigen, die den Empfänger nennt und den Nutzer per Passkey anmeldet. Erst nach erfolgreicher Passkey-Prüfung eines aktiven Kontos MUST ein einmal verwendbarer Code mit 60 Sekunden Laufzeit entstehen. Eine unbekannte `client_id` oder eine nicht registrierte `redirect_uri` MUST eine Fehlerseite ohne Weiterleitung ergeben. Ablehnen MUST mit `error=access_denied` zurückleiten.

#### Scenario: Freigabe
- **GIVEN** ChatGPT leitet mit gültigem Client, Redirect-URI, `state` und PKCE-Challenge weiter
- **WHEN** der Nutzer sich mit seinem Passkey anmeldet
- **THEN** leitet die Seite mit `code` und unverändertem `state` an die Redirect-URI zurück

#### Scenario: Unbekannte Redirect-URI
- **GIVEN** die `redirect_uri` gehört nicht zum Client
- **WHEN** die Freigabeseite aufgerufen wird
- **THEN** zeigt die API eine Fehlerseite und leitet nicht weiter

### Requirement: Token-Endpunkt

`POST /api/v1/oauth/token` SHALL einen Code mit passendem `client_id`, `redirect_uri` und `code_verifier` (S256) gegen Access- und Refresh-Token einer neuen verbundenen App tauschen und Refresh-Tokens verbundener Apps rotieren. Ein zweites Einlösen, ein falscher Verifier oder das Refresh-Token einer Geräte-Session MUST mit `invalid_grant` scheitern.

#### Scenario: Code doppelt eingelöst
- **GIVEN** ein Code wurde bereits gegen Tokens getauscht
- **WHEN** er erneut eingelöst wird
- **THEN** antwortet die API mit 400 und `invalid_grant`

#### Scenario: Falscher Verifier
- **GIVEN** ein gültiger Code
- **WHEN** er mit einem nicht passenden `code_verifier` eingelöst wird
- **THEN** antwortet die API mit 400 und `invalid_grant`
