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
