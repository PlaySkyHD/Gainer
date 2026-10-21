# Proposal

## Why

Cardio-Einheiten liegen heute nur in Gainer und optional in Apple Health. Wer seine Ausdauer in Strava verfolgt, muss sie dort von Hand nachtragen und verliert dabei die Pulskurve. Krafttraining soll dagegen nicht automatisch in Strava landen, weil es dort für viele nur den Feed füllt.

## What Changes

1. **Strava verbinden:** Unter „Mehr“ gibt es „Strava“. Der Nutzer verbindet sein Strava-Konto über den Strava-Login im System-Browser-Sheet (OAuth). Client-Secret und Tokens bleiben im Backend.
2. **Automatischer Export:** Nach dem Verbinden sendet der Server neue, beendete Einheiten der eingeschalteten Arten an Strava:
   - **Cardio-Einheiten** (Standard an) als TCX-Datei mit Pulskurve, Distanz und Energie, als Indoor-Fahrt (`trainer`).
   - **Krafttraining** (Standard aus) als Aktivität „Weight Training“ mit Dauer und Übungsübersicht.
3. **Einstellbar:** Beide Arten lassen sich getrennt ein- und ausschalten. Eingeschaltet wird ab diesem Zeitpunkt exportiert, nicht rückwirkend.
4. **Einzeln senden:** Die Cardio-Detailansicht zeigt den Strava-Stand und bietet „An Strava senden“ für ältere oder fehlgeschlagene Einheiten.
5. **Trennen:** „Verbindung trennen“ widerruft den Zugriff bei Strava und löscht die Tokens.

### Non-Goals

- Kein Import aus Strava, kein Lesen fremder Aktivitäten.
- Spätere Änderungen oder Löschungen einer Einheit werden nicht zu Strava übertragen.
- Kein rückwirkender Massenexport; ältere Einheiten nur einzeln.
- Keine Strava-Webhooks (Widerruf in Strava erkennt der Server beim nächsten Token-Refresh).

## Zuordnung

Private Kernjourney (Cardio), optionale Integration.

## Impact

- **Backend:**
  - Neue Entitäten `StravaConnection` (Tokens verschlüsselt per Data Protection, Einstellungen) und `StravaExport` (Ledger je Einheit) im Schema `integrations`, Migration.
  - `StravaApiClient` (OAuth, Uploads, Aktivitäten), `StravaIntegrationService`, `StravaExportProcessor` und `StravaExportWorker` (Hosted Service im API-Prozess, kein neuer Prozess).
  - Endpunkte unter `/api/v1/integrations/strava`: Status, Autorisierung starten, Callback (anonym, mit verschlüsseltem `state`), Einstellungen, Trennen, Export anfordern und abfragen.
  - Konfiguration `Strava:ClientId`, `Strava:ClientSecretFile`, `Strava:CallbackUrl`; ohne Konfiguration ist die Funktion aus.
- **Pigeon/iOS:** `authenticateWebSession(url, callbackScheme)` über `ASWebAuthenticationSession`.
- **Flutter:** Strava-Screen unter „Mehr“, Strava-Zeile in der Cardio-Detailansicht, API-Aufrufe.
- **Security:**
  - Strava erhält nur die exportierten Einheiten (Zeit, Puls, Distanz, Energie bzw. Übungen und Sätze).
  - Tokens liegen verschlüsselt in PostgreSQL und nie auf dem Gerät.
  - Der `state` ist an Nutzer gebunden, zeitlich begrenzt und nur einmal gültig.
  - Scopes: `read,activity:write`.
- **Breaking Changes:** keine.
