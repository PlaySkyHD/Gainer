# account-security

## ADDED Requirements

### Requirement: Auf allen Geräten abmelden

`POST /api/v1/auth/logout-all` SHALL alle Geräte-Sessions des angemeldeten Kontos widerrufen, auch die eigene. Passkeys MUST erhalten bleiben. Die App MUST sich erst lokal abmelden, wenn der Server zugestimmt hat, und die Funktion ohne Verbindung deaktivieren.

#### Scenario: Zwei Geräte
- **GIVEN** das Konto ist auf iPhone und iPad angemeldet
- **WHEN** der Nutzer auf dem iPhone „Auf allen Geräten abmelden“ bestätigt
- **THEN** liefern beide Access-Tokens 401, und eine Anmeldung per Passkey funktioniert weiter

#### Scenario: Server nicht erreichbar
- **WHEN** der Aufruf scheitert
- **THEN** bleibt das iPhone angemeldet, und ein Dialog erklärt, dass die anderen Geräte nicht abgemeldet wurden

### Requirement: Login verrät keine Konten

Für eine unbekannte E-Mail-Adresse und für gesperrte, inaktive oder unbestätigte Konten SHALL der Login einen Passwort-Hash berechnen, damit die Antwortzeit der einer falschen Passwortangabe entspricht. Die Antwort MUST in allen Fällen 401 mit Code `invalid_credentials` sein.

#### Scenario: Unbekannte E-Mail
- **WHEN** sich jemand mit einer unbekannten E-Mail-Adresse anmeldet
- **THEN** antwortet die API nach einer Passwortprüfung mit 401 `invalid_credentials`

### Requirement: Kein Einblick im App-Switcher

Die App SHALL beim Wechsel in den Hintergrund ihren Inhalt mit einer Unschärfe verdecken und sie beim Zurückkehren entfernen. System-Sheets wie Face ID MUST NOT die Unschärfe auslösen.

#### Scenario: App-Switcher
- **WHEN** der Nutzer die App in den Hintergrund schickt
- **THEN** zeigt der App-Switcher eine unscharfe Vorschau
