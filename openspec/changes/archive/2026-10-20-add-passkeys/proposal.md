# Proposal

## Why

Seit `mobile-token-auth` bleibt die App 60 Tage angemeldet. Für die Anmeldung selbst braucht es aber weiter E-Mail und Passwort. Passkeys erlauben die Anmeldung per Face ID: ohne Passwort, sicher gegen Phishing, und dank iCloud-Schlüsselbund auch auf einem neuen iPhone.

## What Changes

- **Server:** .NET-10-Identity-Passkeys (`IPasskeyHandler`) mit Relying Party `gainer.markfort.xyz`, Nutzerverifikation Pflicht. Neue Tabelle `identity.user_passkeys` (Identity-Schema 3).
- **Endpunkte unter `/api/v1/auth/passkeys`:** Optionen und Registrierung für angemeldete Konten, Liste, Entfernen, sowie anonym Anmeldeoptionen und Login. Der Login startet eine Geräte-Session wie die Passwort-Anmeldung.
- **Ceremony-Zustand:** Der Zustand des Handlers geht verschlüsselt (Data Protection) an die App, gilt 5 Minuten, ist an Konto und Vorgang gebunden und wird nur einmal angenommen.
- **Widerrufene Access-Tokens** gelten jetzt als „nicht angemeldet“ statt den Request abzuweisen. Geschützte Endpunkte antworten weiter mit 401, Anmelde-Endpunkte funktionieren auch mit veraltetem Token.
- **Domain:** Der Edge-Container liefert `/.well-known/apple-app-site-association` mit `webcredentials` für `Q7GTYQ282F.xyz.markfort.gainer`.
- **iOS:** Entitlement `webcredentials:gainer.markfort.xyz`, `NativePasskeys.swift` mit `ASAuthorizationPlatformPublicKeyCredentialProvider`, zwei neue Pigeon-Methoden. Der Workflow prüft, dass das Provisioning-Profil Associated Domains enthält.
- **App:** „Mit Passkey anmelden“ im Login, „Mehr → Passkeys“ zum Anlegen und Entfernen.

### Non-Goals

- Passwort bleibt gültig; Passkeys sind ein zusätzlicher Weg.
- Kein automatischer Hinweis nach der Passwort-Anmeldung, einen Passkey anzulegen.
- Keine Passkeys bei der Einladungsannahme; dort wird weiter ein Passwort gesetzt.
- Keine Attestation-Prüfung der Authenticator-Hersteller (`none`).

## Capabilities

- **Neu:** `passkey-sign-in`.

## Impact

- API: nur neue Endpunkte und Schemata, keine Vertragsbrüche.
- Datenbank: Migration `AddUserPasskeys`.
- Apple: Associated Domains auf der App-ID aktivieren, App-Profil neu erzeugen und als `IOS_PROVISIONING_PROFILE_BASE64` hinterlegen. Ohne das scheitert der signierte Build mit klarer Meldung.
- Tests: neue Testabhängigkeit `System.Formats.Cbor` für einen Software-Authenticator.
