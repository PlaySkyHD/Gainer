## ADDED Requirements

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

Der MCP-Server SHALL die Tools `get_overview`, `list_workouts`, `get_workout`, `search_exercises` und `get_exercise_progress` anbieten, alle als nur lesend gekennzeichnet. Sie MUST ausschließlich Daten des Nutzers der verbundenen App liefern und MUST NOT Daten schreiben.

#### Scenario: Fremdes Training
- **GIVEN** Nutzer B besitzt ein Training
- **WHEN** die verbundene App von Nutzer A `get_workout` mit dessen ID aufruft
- **THEN** meldet das Tool, dass das Training nicht gefunden wurde

#### Scenario: Überblick
- **GIVEN** Nutzer A hat in den letzten 30 Tagen trainiert und gewogen
- **WHEN** die verbundene App `get_overview` mit 30 Tagen aufruft
- **THEN** enthält die Antwort Trainingsanzahl, Volumen, Gewichtsdurchschnitt und Ernährungsdurchschnitte dieses Zeitraums

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
