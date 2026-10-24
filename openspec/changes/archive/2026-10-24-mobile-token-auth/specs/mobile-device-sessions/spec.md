# mobile-device-sessions

## ADDED Requirements

### Requirement: Anmeldung erzeugt eine Geräte-Session

`POST /api/v1/auth/login` SHALL bei gültigen Zugangsdaten eines aktiven, bestätigten Kontos mit 200 einen Access-Token, dessen Laufzeit in Sekunden, einen Refresh-Token und dessen Ablaufzeit liefern und eine Geräte-Session mit dem übergebenen Gerätenamen anlegen. Die Antwort MUST NOT ein Cookie setzen. Der Refresh-Token MUST nur als SHA-256-Hash gespeichert werden. Unbekanntes Konto und falsches Passwort MUST dieselbe 401-Antwort mit Code `invalid_credentials` liefern.

#### Scenario: Erfolgreiche Anmeldung
- **GIVEN** ein aktives Konto `athlete@example.test`
- **WHEN** die App sich mit richtigem Passwort und Gerätename „Gainer iPhone“ anmeldet
- **THEN** antwortet die API mit 200, `expiresIn` 900 und einem Refresh-Token, ohne `Set-Cookie`, und `identity.device_sessions` enthält eine Session „Gainer iPhone“ mit 32-Byte-Hash

#### Scenario: Falsches Passwort
- **WHEN** die App sich mit falschem Passwort anmeldet
- **THEN** antwortet die API mit 401 und Code `invalid_credentials`, wie bei einem unbekannten Konto

### Requirement: Refresh rotiert und gleitet

`POST /api/v1/auth/refresh` SHALL für den aktuellen Refresh-Token einer aktiven Session ein neues Token-Paar liefern, den alten Token ersetzen und die Session auf 60 Tage ab jetzt verlängern. Eine Session ohne Refresh MUST nach 60 Tagen ablaufen.

#### Scenario: Regelmäßige Nutzung
- **GIVEN** eine Session, die alle 50 Tage erneuert wird
- **WHEN** 200 Tage vergangen sind
- **THEN** ist die Session weiterhin gültig und läuft 60 Tage nach dem letzten Refresh ab

#### Scenario: Lange nicht genutzt
- **GIVEN** eine Session, deren letzter Refresh 60 Tage und 1 Sekunde zurückliegt
- **WHEN** die App den Refresh-Token einlöst
- **THEN** antwortet die API mit 401 und Code `invalid_refresh_token`

### Requirement: Wiederverwendung widerruft die Session

Wird ein bereits ersetzter Refresh-Token mehr als eine Minute nach der Rotation erneut eingelöst, SHALL die API mit 401 antworten und die Session widerrufen. Innerhalb dieser Minute SHALL sie ihn genau einmal mehr akzeptieren und ein neues Paar ausstellen; der zuletzt ausgestellte Token wird dadurch verworfen. Kommt der verworfene Token später zurück oder folgt ein zweiter Retry vor der nächsten Rotation, MUST die API die Session widerrufen.

#### Scenario: Gestohlener Token
- **GIVEN** Token A wurde gegen Token B getauscht
- **WHEN** zwei Minuten später Token A eingelöst wird
- **THEN** antwortet die API mit 401, und weder Token B noch der zugehörige Access-Token funktionieren noch

#### Scenario: Verlorene Antwort
- **GIVEN** Token A wurde gegen Token B getauscht, die Antwort kam nicht an
- **WHEN** die App 20 Sekunden später Token A erneut einlöst
- **THEN** erhält sie Token C, und Token C funktioniert

#### Scenario: Gestohlener Token in der Kulanzminute
- **GIVEN** das Gerät hat Token A gegen Token B getauscht, ein Angreifer löst 20 Sekunden später Token A ein und erhält Token C
- **WHEN** das Gerät Token B einlöst
- **THEN** antwortet die API mit 401, und weder Token C noch der zugehörige Access-Token funktionieren noch

### Requirement: Widerruf wirkt sofort

Jeder Bearer-authentifizierte Request SHALL abgelehnt werden, wenn seine Geräte-Session widerrufen oder abgelaufen ist oder das Konto deaktiviert wurde. Logout SHALL die eigene Session widerrufen; Deaktivieren eines Kontos SHALL alle seine Sessions widerrufen, auch für eine spätere Reaktivierung.

#### Scenario: Logout
- **WHEN** die App sich abmeldet
- **THEN** liefern der bisherige Access-Token und der Refresh-Token 401

#### Scenario: Deaktivierung
- **GIVEN** ein angemeldetes Konto
- **WHEN** der Operator es deaktiviert und später wieder aktiviert
- **THEN** liefert der alte Access-Token sofort 401, und der alte Refresh-Token bleibt auch nach der Reaktivierung ungültig

### Requirement: Keine Browser-Mechanismen

Die API SHALL keine Cookie-Authentifizierung, kein Antiforgery und keine Origin-Prüfung mehr anbieten. `GET /api/v1/auth/antiforgery` MUST 404 liefern. Ein Cookie MUST NOT authentifizieren.

#### Scenario: Fremder Origin
- **WHEN** ein Login mit `Origin: https://attacker.example` eintrifft
- **THEN** behandelt die API ihn wie jeden anderen Login, ohne 403

### Requirement: App hält die Session selbstständig

Die App SHALL den Access-Token vor Ablauf und nach einem 401 genau einmal erneuern, parallele Requests mit einem Refresh bedienen und nach jeder Rotation den Keychain-Checkpoint mit dem neuen Refresh-Token überschreiben. Der Checkpoint MUST NOT Passwort oder Access-Token enthalten. Checkpoints der Version 1 MUST verworfen werden. Lehnt der Server den Refresh ab, SHALL die App das Konto schließen, den Checkpoint löschen und die Anmeldung mit dem Hinweis zeigen, dass lokale Daten erhalten bleiben.

#### Scenario: Neustart
- **GIVEN** die App wurde beendet und hat nur den Refresh-Token im Keychain
- **WHEN** sie neu startet
- **THEN** erneuert sie die Tokens, öffnet das Konto online und speichert den neuen Refresh-Token

#### Scenario: Paralleler Ablauf
- **GIVEN** der Access-Token läuft in weniger als 30 Sekunden ab
- **WHEN** zwei Requests gleichzeitig starten
- **THEN** sendet die App genau einen Refresh und beide Requests mit dem neuen Access-Token

#### Scenario: Session widerrufen
- **GIVEN** die Session wurde serverseitig widerrufen
- **WHEN** die App den Refresh-Token einlöst
- **THEN** zeigt sie die Anmeldung mit „Deine Anmeldung ist abgelaufen …“ und der Checkpoint ist gelöscht

#### Scenario: Update von einem Cookie-Build
- **GIVEN** im Keychain liegt ein Checkpoint der Version 1
- **WHEN** die neue App startet
- **THEN** verwirft sie ihn und zeigt die Anmeldung
