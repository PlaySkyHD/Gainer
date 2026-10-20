# passkey-sign-in

## ADDED Requirements

### Requirement: Neuer Passkey nur mit frischer Bestätigung

`POST /api/v1/auth/passkeys/creation-options` SHALL nur Optionen liefern, wenn die Geräte-Session des Requests höchstens 5 Minuten zuvor angemeldet wurde oder der Body das richtige Passwort enthält. Andernfalls MUST die API mit 403 und Code `reauthentication_required` antworten, und die App MUST das Passwort abfragen und erneut senden.

#### Scenario: Direkt nach der Anmeldung
- **GIVEN** der Nutzer hat sich vor einer Minute angemeldet
- **WHEN** er einen Passkey hinzufügt
- **THEN** startet Face ID ohne Passwortabfrage

#### Scenario: Später
- **GIVEN** die Anmeldung liegt sechs Minuten zurück
- **WHEN** der Nutzer einen Passkey hinzufügt
- **THEN** fragt die App das Passwort ab und legt den Passkey erst danach an

#### Scenario: Falsches Passwort
- **WHEN** der Nutzer ein falsches Passwort eingibt
- **THEN** antwortet die API mit 403, und die App meldet „Das Passwort war falsch.“
