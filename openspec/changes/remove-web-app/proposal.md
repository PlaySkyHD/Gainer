# Proposal

## Why

Die Next.js-PWA in `apps/web` wird nicht mehr genutzt. Alle Funktionen samt Kontoverwaltung und Einladungsannahme gibt es in der iOS-App. Die Web-App kostet trotzdem Pflege: ein npm-Abhängigkeitsbaum, ein eigener Build im Edge-Image, CSP-Generierung, Playwright-Tests und Lizenzprüfung in der CI. Außerdem hält sie die browserbasierte Cookie- und CSRF-Authentifizierung am Leben, die für die geplante Token-Authentifizierung der App wegfallen soll.

## What Changes

- **Entfernen:** `apps/web` vollständig, dazu `deploy/generate-edge-csp.mjs`, `scripts/check-npm-licenses.mjs` und die PWA-Abnahmecheckliste `deploy/NUTRITION_IPHONE_ACCEPTANCE.md`.
- **Edge:** Das Edge-Image ist nur noch Caddy mit statischer Konfiguration. Es leitet `/api/v1/*` und `/health/*` an die API weiter und beantwortet alle anderen Pfade mit 404. Die CSP lautet `default-src 'none'; frame-ancestors 'none'`. Image-Name, Port und Compose-Topologie bleiben gleich, damit sich am Host-Caddy und am Deploy-Workflow nichts ändert.
- **CI und Skripte:** Node-Setup, npm-Install, TypeScript-Vertragsgenerierung, Typecheck, Lint, statischer Build, CSP-Prüfung, npm-Lizenzprüfung, Edge-Hydration- und Browsertests entfallen. Neu ist ein Smoke-Test des Edge-Containers (404 und CSP-Header). Die OpenAPI-Driftprüfung bleibt für `contracts/openapi`.
- **Aspire AppHost:** Die Ressource `web` und das Paket `Aspire.Hosting.JavaScript` entfallen. Lokal ist `Security:FrontendOrigin` der eigene API-Endpunkt, so wie ihn die iOS-App ohne Überschreibung sendet.
- **Doku:** README, Runbook, Lizenzhinweise, Beitragsrichtlinie und der OpenSpec-Projektkontext beschreiben die iOS-App als einzigen Client.

### Non-Goals

- Keine Änderung an der Authentifizierung. Cookie-Session, Antiforgery und Origin-Prüfung bleiben bestehen, weil die iOS-App sie noch nutzt. Die Umstellung auf Tokens ist ein eigener Change.
- Keine Änderung an API-Verträgen, Datenbank oder Sync. Sync-Handover-Endpunkte bleiben, weil die App sie für Gerätewechsel nutzt.
- Abgeschlossene oder offene OpenSpec-Changes mit PWA-Bezug werden nicht umgeschrieben.

## Capabilities

- **Neu:** `web-client-retirement`.

## Impact

- Gelöscht: `apps/web`, Web-spezifische Skripte und Dokumente.
- Geändert: `deploy/Dockerfile.edge`, `deploy/Caddyfile`, `.github/workflows/ci.yml`, `scripts/verify.ps1`, `src/Gainer.AppHost`, `Directory.Packages.props`, Lockfiles, AppHost-Topologietest, `appsettings.Development.json`, Doku.
- Betrieb: Nach dem nächsten Deploy liefert `https://gainer.markfort.xyz/` 404 statt der PWA. Die API unter `/api/v1` ist unverändert erreichbar.
