# Proposal

## Why

Nutzer sollen ihre Daten jederzeit vollständig mitnehmen können: als Sicherung auf eigene Faust, zum Auswerten in anderen Werkzeugen und als Datenübertragbarkeit nach DSGVO Art. 20. Bisher gibt es nur den Export einzelner Cardio-Einheiten nach Apple Health (Issue #109).

## What Changes

- **Endpunkt `GET /api/v1/account/export`:** liefert alle fachlichen Daten des angemeldeten Nutzers als eine JSON-Datei. Grundlage ist der aktuelle Stand jeder Sync-Ressource (Ziele, Check-ins, eigene Übungen und Kategorien, Pläne, Rhythmus, Trainings, Cardio, Ernährungstage, Gerichte, Tagesvorlagen, Ernährungsziele). Gelöschte Ressourcen fehlen.
- **Format:** Kopf mit `format`, `schemaVersion`, Sync-Protokollversion, Zeitpunkt und Server-Revision, danach die Ressourcen im Snapshot-Format des Sync-Feeds.
- **Begrenzung:** eigenes Rate-Limit pro Nutzer.
- **App:** Eintrag „Daten exportieren“ unter „Mehr“ → „Konto & Geräte“. Der Export wird als Datei über das iOS-Teilen-Sheet weitergegeben (Dateien, AirDrop, Mail).

### Non-Goals

- Kein Import, auch nicht des eigenen Exports. Das versionierte Format hält ihn offen.
- Keine Konto- und Sicherheitsdaten (Passkeys, Sessions, Geräte, Strava-Verbindung) und keine Sync-Protokolldaten.
- Keine CSV- oder PDF-Ausgabe.

## Capabilities

- **Geändert:** `account-access` (neue Anforderung „Export der eigenen Daten“).

## Impact

- Backend: neue Core-Schnittstelle, Abfrage über `sync.change_items`, Controller, Vertrag, Rate-Limit, OpenAPI.
- Flutter: API-Aufruf, Export-Screen, Pigeon-Methode `shareFile` mit Swift-Umsetzung (`UIActivityViewController`).
- Keine Migration, keine Sync-Änderung.
