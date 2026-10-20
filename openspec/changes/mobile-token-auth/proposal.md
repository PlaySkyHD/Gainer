# Proposal

## Why

Die iOS-App meldet sich wie ein Browser an: ASP.NET-Identity-Cookie mit fester Laufzeit von 12 Stunden, dazu Antiforgery-Token und ein vorgetäuschter `Origin`-Header. Nach spätestens 12 Stunden muss man sich neu anmelden, auch mitten in der Woche oder vor dem Training. Seit die Web-App entfernt ist (`remove-web-app`), gibt es keinen Browser-Client mehr, für den Cookie, CSRF-Schutz und Origin-Prüfung nötig wären.

## What Changes

- **Geräte-Sessions:** Neue Tabelle `identity.device_sessions`. Login legt eine Session an und liefert einen Access-Token (15 Minuten) und einen Refresh-Token. Gespeichert wird nur der SHA-256-Hash des Refresh-Tokens.
- **Refresh mit Rotation:** `POST /api/v1/auth/refresh` tauscht den Refresh-Token gegen ein neues Paar. Jede Nutzung verlängert die Session auf 60 Tage ab jetzt. Kommt ein bereits ersetzter Token nach mehr als einer Minute zurück, wird die Session widerrufen. Innerhalb dieser Minute wird er noch einmal akzeptiert, damit eine verlorene Antwort nicht abmeldet.
- **Sofortiger Widerruf:** Jeder Request prüft, ob die Session noch aktiv und das Konto aktiv ist. Logout widerruft die eigene Session, Deaktivieren durch den Operator alle Sessions des Kontos.
- **Entfernt:** Cookie-Authentifizierung, `GET /api/v1/auth/antiforgery`, Antiforgery-Filter, `RequestOriginMiddleware`, Entwicklungs-CORS und die Einstellung `Security:FrontendOrigin` samt `GAINER_PUBLIC_ORIGIN` und `GAINER_TRUSTED_FRONTEND_ORIGIN`.
- **Rate-Limit:** Login und Refresh sind auf 30 Anfragen pro Minute und IP begrenzt.
- **App:** `ApiClient` sendet `Authorization: Bearer`, erneuert den Access-Token vor Ablauf und nach einem 401 genau einmal und teilt einen laufenden Refresh zwischen parallelen Requests. Der Keychain-Checkpoint (Version 2) enthält nur den Refresh-Token und wird nach jeder Rotation neu geschrieben. Lehnt der Server die Session ab, meldet die App ab und weist darauf hin, dass lokale Daten erhalten bleiben. CookieJar, `dio_cookie_manager` und CSRF entfallen.

### Non-Goals

- Keine Geräteliste in der App und kein Abmelden einzelner fremder Geräte; die Tabelle macht das später möglich.
- Kein OAuth/OIDC, keine Passkeys, kein „Passwort vergessen“.
- Keine harte Obergrenze der Session-Laufzeit. `Security:DeviceSessions:AbsoluteLifetime` erlaubt sie später ohne Codeänderung.

## Capabilities

- **Neu:** `mobile-device-sessions`.

## Impact

- API: Login-Antwort ändert sich von 204 auf 200 mit Token-Paar; `/auth/antiforgery` entfällt. Beides steht in `contracts/openapi/accepted-breaking-changes.json`.
- Datenbank: Migration `AddDeviceSessions`.
- Nutzer: Nach dem Update auf den neuen Build ist einmal eine neue Anmeldung nötig, weil alte Cookie-Checkpoints nicht übernommen werden. Ältere App-Builds können sich nach dem Deploy nicht mehr anmelden.
- Betrieb: `GAINER_PUBLIC_ORIGIN` in `/etc/gainer/deployment.env` wird nicht mehr gelesen und kann entfernt werden.
