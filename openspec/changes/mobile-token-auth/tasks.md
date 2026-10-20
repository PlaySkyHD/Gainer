# Tasks

## 1. Backend

- [x] 1.1 `DeviceSession`, Migration `AddDeviceSessions`, `IDeviceSessionService` mit Rotation, Kulanzzeit, Wiederverwendungserkennung und gleitender Laufzeit (D2, D3, D5).
- [x] 1.2 Bearer-Authentifizierung mit `AccessTokenIssuer` und `DeviceSessionValidationMiddleware` (D1, D4); Cookie, Antiforgery, Origin-Prüfung und Entwicklungs-CORS entfernen.
- [x] 1.3 Endpunkte Login, Refresh, Session, Logout; Rate-Limit; Deaktivierung widerruft Sessions.
- [x] 1.4 Integrationstests auf Bearer umstellen; Tests für Rotation, Kulanz, Wiederverwendung, Gleiten, Ablauf, Deaktivierung und fehlende Browser-Mechanismen.
- [x] 1.5 OpenAPI-Vertrag und `accepted-breaking-changes.json`; `Security:FrontendOrigin`/`GAINER_PUBLIC_ORIGIN` aus Compose, AppHost, CI und Runbook entfernen.

## 2. App

- [x] 2.1 `ApiClient` mit Bearer, Refresh vor Ablauf und nach 401, gebündeltem Refresh und Rückrufen (D6); CookieJar und CSRF entfernen.
- [x] 2.2 Checkpoint Version 2 mit Refresh-Token, Neuschreiben nach Rotation, Offline-Wiederherstellung über `ApiSessionService`.
- [x] 2.3 `MobileAuthController` meldet bei abgelehnter Session ab; Einladungslink aus dem API-Ursprung; `GAINER_TRUSTED_FRONTEND_ORIGIN` entfernen.
- [x] 2.4 Tests für Token-Fluss, Rotation, Parallelität, 401-Wiederholung, Ablehnung und Controller-Abmeldung.

## 3. Abschluss

- [ ] 3.1 Nach Merge `accepted-breaking-changes.json` leeren.
- [ ] 3.2 Production-Deploy, dann TestFlight; auf dem iPhone einmal neu anmelden, App über Nacht liegen lassen und prüfen, dass sie angemeldet bleibt und synchronisiert.
