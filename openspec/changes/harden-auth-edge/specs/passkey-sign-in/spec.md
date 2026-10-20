# passkey-sign-in

## MODIFIED Requirements

### Requirement: Mit Passkey anmelden

`POST /api/v1/auth/passkeys/request-options` und `POST /api/v1/auth/passkeys/login` SHALL ohne Anmeldung eine Geräte-Session mit Token-Paar starten, wenn die Assertion gültig ist und das Konto aktiv und bestätigt ist. Eine Sperre nach falschen Passwörtern MUST NOT die Passkey-Anmeldung verhindern. Andernfalls MUST die API mit 401 und Code `invalid_passkey` antworten. Ein Zustand MUST nur einmal angenommen werden.

#### Scenario: Anmeldung per Face ID
- **GIVEN** ein Konto mit Passkey
- **WHEN** der Nutzer im Login „Mit Passkey anmelden“ wählt und Face ID bestätigt
- **THEN** ist die App angemeldet und die Geräte-Session heißt „Gainer iPhone“

#### Scenario: Wiederholte Assertion
- **WHEN** dieselbe Assertion mit demselben Zustand ein zweites Mal eingereicht wird
- **THEN** antwortet die API mit 401

#### Scenario: Gesperrt nach falschen Passwörtern
- **GIVEN** ein Konto mit Passkey, gesperrt nach fünf falschen Passwörtern
- **WHEN** der Nutzer sich mit dem Passkey anmeldet
- **THEN** antwortet die API mit 200 und einem Token-Paar

#### Scenario: Deaktiviertes Konto
- **GIVEN** das Konto des Passkeys ist deaktiviert
- **WHEN** der Nutzer sich mit dem Passkey anmeldet
- **THEN** antwortet die API mit 401

#### Scenario: Abbruch
- **WHEN** der Nutzer das System-Sheet abbricht
- **THEN** sendet die App keinen Login und bleibt im bisherigen Zustand
