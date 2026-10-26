## MODIFIED Requirements

### Requirement: Keine Browser-Mechanismen

Die API SHALL keine Cookie-Authentifizierung, kein Antiforgery und keine Origin-Prüfung mehr anbieten. `GET /api/v1/auth/antiforgery` MUST 404 liefern. Ein Cookie MUST NOT authentifizieren.

#### Scenario: Fremder Origin
- **GIVEN** ein Konto mit gültigen Zugangsdaten
- **WHEN** ein Login mit `Origin: https://attacker.example` eintrifft
- **THEN** behandelt die API ihn wie jeden anderen Login, ohne 403

### Requirement: Passkeys verwalten

Ein angemeldetes Konto SHALL seine Passkeys auflisten und einzeln entfernen können. Ein entfernter Passkey MUST NOT mehr anmelden. Ohne Verbindung MUST die App das Anlegen deaktivieren und erklären, warum.

#### Scenario: Entfernen
- **GIVEN** ein angemeldetes Konto hat einen Passkey „Gainer iPhone“
- **WHEN** der Nutzer einen Passkey nach links wischt und bestätigt
- **THEN** antwortet die API mit 204, und eine Anmeldung mit diesem Passkey liefert 401

### Requirement: Domain-Bindung

Der Edge-Container SHALL unter `/.well-known/apple-app-site-association` JSON mit `webcredentials.apps = ["Q7GTYQ282F.xyz.markfort.gainer"]` ausliefern. Die App MUST das Entitlement `webcredentials:gainer.markfort.xyz` tragen, und der signierte Build MUST abbrechen, wenn das Provisioning-Profil Associated Domains nicht enthält.

#### Scenario: Apple fragt die Domain ab
- **GIVEN** der Edge-Container läuft und die App ist für `gainer.markfort.xyz` eingerichtet
- **WHEN** `GET https://gainer.markfort.xyz/.well-known/apple-app-site-association` eintrifft
- **THEN** antwortet der Edge mit 200, `Content-Type: application/json` und der App-ID

### Requirement: Login verrät keine Konten

Für eine unbekannte E-Mail-Adresse und für gesperrte, inaktive oder unbestätigte Konten SHALL der Login einen Passwort-Hash berechnen, damit die Antwortzeit der einer falschen Passwortangabe entspricht. Die Antwort MUST in allen Fällen 401 mit Code `invalid_credentials` sein.

#### Scenario: Unbekannte E-Mail
- **GIVEN** zu der eingegebenen E-Mail-Adresse existiert kein Konto
- **WHEN** sich jemand mit dieser E-Mail-Adresse anmeldet
- **THEN** antwortet die API nach einer Passwortprüfung mit 401 `invalid_credentials`

### Requirement: Kein Einblick im App-Switcher

Die App SHALL beim Wechsel in den Hintergrund ihren Inhalt mit einer Unschärfe verdecken und sie beim Zurückkehren entfernen. System-Sheets wie Face ID MUST NOT die Unschärfe auslösen.

#### Scenario: App-Switcher
- **GIVEN** die App zeigt geschützte Inhalte
- **WHEN** der Nutzer die App in den Hintergrund schickt
- **THEN** zeigt der App-Switcher eine unscharfe Vorschau

### Requirement: Größenlimit pro Endpunkt

Request-Bodies SHALL höchstens 1 MiB groß sein, außer ein Endpunkt erlaubt mit `[RequestSizeLimit]` mehr. Die Mahlzeit-Schätzung MUST Requests bis 8 MiB annehmen und größere mit 413 ablehnen.

#### Scenario: Foto über 1 MiB
- **GIVEN** die App hat ein 3 MB großes Foto für die Mahlzeit-Schätzung ausgewählt
- **WHEN** die App das Foto sendet
- **THEN** erreicht es die Schätzung

#### Scenario: Großer Body an einem anderen Endpunkt
- **GIVEN** ein Endpunkt ohne `[RequestSizeLimit]`-Erlaubnis für mehr als 1 MiB
- **WHEN** ein 2-MiB-Body an diesen Endpunkt geht
- **THEN** antwortet die API mit 413
