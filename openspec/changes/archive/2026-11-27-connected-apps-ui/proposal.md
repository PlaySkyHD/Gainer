# Proposal

## Why

Die API listet und widerruft verbundene Apps (Anforderung „Verbundene Apps verwalten“), aber die App zeigt sie nicht. Der Nutzer sieht nicht, welche Assistenten Zugriff haben, und kann ChatGPT nur über die API trennen.

## What Changes

- Neuer Screen „Verbundene Apps“ im Profil direkt unter „Passkeys“: je Verbindung Name, Verbindungsdatum und letzte Nutzung.
- Trennen per Wischen mit Bestätigung oder per Tippen über ein Aktions-Sheet; danach lädt die Liste neu.
- Leerer Zustand erklärt kurz die Einrichtung in ChatGPT mit der kopierbaren MCP-Adresse.
- Lade-, Fehler- und Offline-Zustand mit „Erneut versuchen“.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `account-access`: App-Screen für verbundene Apps.

## Impact

App: `ApiClient` (`listConnectors`, `deleteConnector`), `ApiConnectorSession`, `MobileAuthController`, neuer `ConnectedAppsScreen`, Eintrag in der Profilliste, `formatGermanDate` in `lib/ui/core/german_date_time.dart`. Kein Backend- oder Vertragswechsel.
