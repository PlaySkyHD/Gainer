# passkey-sign-in Specification

## Purpose
Angemeldete Nutzer legen auf dem iPhone Passkeys an und melden sich danach ohne Passwort mit Face ID an. Der Server prüft die WebAuthn-Zeremonie und startet bei Erfolg eine normale Gerätesitzung.

## Requirements

### Requirement: Passkey anlegen

Ein angemeldetes Konto SHALL über `POST /api/v1/auth/passkeys/creation-options` und `POST /api/v1/auth/passkeys` einen Passkey für die Relying Party `gainer.markfort.xyz` mit Nutzerverifikation anlegen können. Antworten mit anderer Origin, mit fremdem, verändertem, abgelaufenem oder bereits genutztem Zustand MUST mit 400 und Code `passkey_rejected` abgelehnt werden.

#### Scenario: Passkey hinzufügen
- **GIVEN** ein angemeldetes Konto ohne Passkey
- **WHEN** der Nutzer unter „Mehr → Passkeys“ einen Passkey hinzufügt und Face ID bestätigt
- **THEN** antwortet die API mit 201, und die Liste zeigt „Gainer iPhone“ mit Erstelldatum

#### Scenario: Fremde Origin
- **WHEN** eine Registrierung mit Origin `https://attacker.example` eintrifft
- **THEN** antwortet die API mit 400 und es wird kein Passkey gespeichert

#### Scenario: Zustand eines anderen Kontos
- **GIVEN** Konto A hat Registrierungsoptionen erhalten
- **WHEN** Konto B die Antwort mit dem Zustand von A einreicht
- **THEN** antwortet die API mit 400, und A kann den Zustand danach noch selbst einlösen

### Requirement: Mit Passkey anmelden

`POST /api/v1/auth/passkeys/request-options` und `POST /api/v1/auth/passkeys/login` SHALL ohne Anmeldung eine Geräte-Session mit Token-Paar starten, wenn die Assertion gültig ist und das Konto aktiv, bestätigt und nicht gesperrt ist. Andernfalls MUST die API mit 401 und Code `invalid_passkey` antworten. Ein Zustand MUST nur einmal angenommen werden.

#### Scenario: Anmeldung per Face ID
- **GIVEN** ein Konto mit Passkey
- **WHEN** der Nutzer im Login „Mit Passkey anmelden“ wählt und Face ID bestätigt
- **THEN** ist die App angemeldet und die Geräte-Session heißt „Gainer iPhone“

#### Scenario: Wiederholte Assertion
- **WHEN** dieselbe Assertion mit demselben Zustand ein zweites Mal eingereicht wird
- **THEN** antwortet die API mit 401

#### Scenario: Deaktiviertes Konto
- **GIVEN** das Konto des Passkeys ist deaktiviert
- **WHEN** der Nutzer sich mit dem Passkey anmeldet
- **THEN** antwortet die API mit 401

#### Scenario: Abbruch
- **WHEN** der Nutzer das System-Sheet abbricht
- **THEN** sendet die App keinen Login und bleibt im bisherigen Zustand

### Requirement: Passkeys verwalten

Ein angemeldetes Konto SHALL seine Passkeys auflisten und einzeln entfernen können. Ein entfernter Passkey MUST NOT mehr anmelden. Ohne Verbindung MUST die App das Anlegen deaktivieren und erklären, warum.

#### Scenario: Entfernen
- **WHEN** der Nutzer einen Passkey nach links wischt und bestätigt
- **THEN** antwortet die API mit 204, und eine Anmeldung mit diesem Passkey liefert 401

### Requirement: Domain-Bindung

Der Edge-Container SHALL unter `/.well-known/apple-app-site-association` JSON mit `webcredentials.apps = ["Q7GTYQ282F.xyz.markfort.gainer"]` ausliefern. Die App MUST das Entitlement `webcredentials:gainer.markfort.xyz` tragen, und der signierte Build MUST abbrechen, wenn das Provisioning-Profil Associated Domains nicht enthält.

#### Scenario: Apple fragt die Domain ab
- **WHEN** `GET https://gainer.markfort.xyz/.well-known/apple-app-site-association` eintrifft
- **THEN** antwortet der Edge mit 200, `Content-Type: application/json` und der App-ID

### Requirement: Veraltete Tokens blockieren keine Anmeldung

Ein Request mit widerrufenem oder abgelaufenem Access-Token SHALL wie ein Request ohne Token behandelt werden. Geschützte Endpunkte MUST mit 401 antworten, Anmelde-Endpunkte MUST normal funktionieren.

#### Scenario: Anmeldung nach Deaktivierung und Reaktivierung
- **GIVEN** ein Client sendet noch den Access-Token einer widerrufenen Session
- **WHEN** er sich mit Passwort neu anmeldet
- **THEN** antwortet die API mit 200 und einem neuen Token-Paar
