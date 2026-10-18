# Design

## Decisions

### D1 – Zusammenfassen je Ressource

`commitMutation` sucht den letzten **noch nicht gesendeten** (Status pending/retry, nie claimed/syncing/sent) Outbox-Eintrag derselben Ressource. Gilt für alle Aggregattypen, deren Mutationsnutzlast den vollständigen Stand enthält (im Code prüfen; Teiloperationen wie Neuordnen oder Zusammenführen ausgenommen). Regeln:

| wartend | neu | Ergebnis |
|---|---|---|
| create | update | create mit neuem Body |
| create | delete | beide entfernen, Ressource lokal entfernen |
| update | update | update mit neuem Body (bisheriges Verhalten, jetzt alle Typen) |
| update | delete | delete mit Basisversion des wartenden Eintrags |
| delete | * | unverändert (gelöschte Ressourcen werden lokal nicht mehr geändert) |

Mutation-ID, Sequenz und Basisversion des wartenden Eintrags bleiben; nur Operation und Body ändern sich. Bereits gesendete Einträge werden nie verändert (Idempotenz).

### D2 – Selbstheilung

Nach einer Ablehnung mit `active_workout_exists`, `validation_failed`, `stale_base_version` oder `resource_not_found` prüft der Push:
- Ressource lokal gelöscht und `serverVersion == null` → Outbox, Ressource und Konflikt entfernen.
- Lokaler Stand neuer als der abgelehnte Body und – für `stale_base_version` – der Server hat seit der gespeicherten `serverVersion` nur eigene Änderungen dieses Geräts → einmalig mit aktuellem Stand und aktueller Basisversion neu einreihen (Mechanik wie `forceLocalState` aus `sync-force-local`), Markierung `autoHealed`, damit es nicht in eine Schleife läuft.
- `validation_failed` wegen fehlender Referenz, deren lokale Anlage noch wartet → nicht als Konflikt, sondern zurück in die Warteschlange (siehe D3).
- Alles andere → Konflikt wie bisher.

### D3 – Abhängigkeiten

Beim Push werden Einträge so geordnet, dass Ressourcen, auf die ein Eintrag verweist (Übungs-IDs in Trainings und Plänen, Kategorie-IDs in Übungen, `sourcePlanId`, `sourceWorkoutId`), zuerst gesendet werden. Ein Eintrag, dessen Referenz noch wartet oder im Konflikt steht, wird in diesem Lauf übersprungen und bleibt pending; er erzeugt keinen Konflikt.

### D4 – Sichtbarkeit

- `SyncStatus` (letzter erfolgreicher Sync, Anzahl wartender Einträge, Schreibgerät ja/nein) als `ValueListenable` aus dem Account-Scope.
- Shell-Banner oberhalb des Inhalts aller Tabs, wenn nicht Schreibgerät: „Dieses iPhone lädt nichts hoch“ + „Übernehmen“ (gleicher Ablauf wie `SyncNowSection`).
- Mehr → Synchronisierung: Fußnote „Zuletzt synchronisiert vor 2 Min. · 3 ausstehend“.
