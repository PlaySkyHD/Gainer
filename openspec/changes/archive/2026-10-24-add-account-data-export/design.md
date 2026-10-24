# Design

## D1: Quelle ist der Sync-Feed

Jede akzeptierte Mutation speichert in `sync.change_items` einen vollständigen Snapshot der Ressource. Ein neues Gerät baut daraus seinen ganzen Stand auf; der Feed ist damit per Konstruktion vollständig. Der Export nimmt pro Ressource (`ResourceType`, `ResourceId`) den Eintrag mit der höchsten `ResourceVersion` und lässt ihn weg, wenn er eine Löschmarkierung ist.

Vorteile: Neue Ressourcenarten landen automatisch im Export, das Format ist dasselbe wie im Sync und bereits versioniert, und es entsteht keine zweite Abbildung jeder Entität. Konto-, Session-, Passkey- und Strava-Daten sind keine Sync-Ressourcen und damit ausgeschlossen.

Die Abfrage läuft unter dem globalen Nutzerfilter von `AppDbContext`. Der Nutzer kommt nur aus der Sitzung; der Endpunkt hat keine Parameter. Lesen geschieht in einer Transaktion mit `RepeatableRead`, damit Revision und Ressourcen zum selben Stand gehören.

## D2: Format

```json
{
  "format": "gainer-account-export",
  "schemaVersion": 1,
  "syncProtocolVersion": 3,
  "exportedAtUtc": "2026-10-24T18:00:00Z",
  "asOfRevision": 812,
  "resources": [
    { "resourceType": "Workout", "resourceId": "…", "version": 4, "snapshot": { … } }
  ]
}
```

Sortiert nach `resourceType`, dann `resourceId`. Die Antwort trägt `Content-Disposition: attachment; filename="gainer-export-JJJJ-MM-TT.json"` und `Cache-Control: no-store`.

## D3: Rate-Limit

Eigene Richtlinie `account-export`: 5 Exporte pro 15 Minuten je Nutzer. Ein Export ist eine teure, seltene Aktion; das Limit schützt vor Endlosschleifen eines Clients.

## D4: App

- „Mehr“ → „Konto & Geräte“ → „Daten exportieren“ öffnet einen Screen mit kurzer Erklärung und der Aktion „Export erstellen“.
- Ohne Verbindung ist die Aktion deaktiviert und der Grund steht darunter.
- Hat das Gerät noch nicht gesendete Änderungen, weist der Screen darauf hin, dass diese im Export fehlen, und bietet „Jetzt synchronisieren“ nicht selbst an (dafür gibt es den Sync-Bereich).
- Die App schreibt die Antwort eingerückt in eine Datei im temporären Verzeichnis, öffnet das Teilen-Sheet über die Pigeon-Methode `shareFile` und löscht die Datei danach.
