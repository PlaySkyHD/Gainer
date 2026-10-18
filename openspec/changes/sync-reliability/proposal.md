# Proposal

## Why

Der Sync spielt jeden lokalen Zwischenschritt einzeln nach (anlegen, jede Änderung, beenden). Hängt ein früher Schritt, blockieren alle folgenden, und der Server lehnt veraltete Zwischenstände ab, etwa ein längst beendetes Training als „aktiv“. Abhängige Ressourcen (Training mit neuer eigener Übung) scheitern, wenn ihre Abhängigkeit noch nicht angekommen ist. Ist das Gerät nicht Schreibgerät, sammelt es unbemerkt Änderungen. Ergebnis: lange Konfliktlisten, die der Nutzer nicht versteht.

## What Changes

1. **Ein wartender Stand je Ressource:** Neue lokale Änderungen ersetzen den noch nicht gesendeten Eintrag derselben Ressource, unabhängig von der Operation. Anlegen + Ändern bleibt ein Anlegen mit neuestem Stand; Anlegen + Löschen entfällt ganz; Ändern + Löschen wird ein Löschen.
2. **Selbstheilung:** Eindeutige Konflikte löst die App ohne Rückfrage: lokal gelöscht und nie auf dem Server → aufräumen; Server lehnt einen veralteten Zwischenstand ab, während lokal ein neuerer Stand existiert und der Server die Ressource seit dem letzten bekannten Stand nicht geändert hat → einmal automatisch mit dem aktuellen lokalen Stand erneut senden. Nur echte Doppeländerungen landen in der Konfliktliste.
3. **Abhängigkeiten abwarten:** Eine Änderung, die auf eine noch nicht bestätigte lokale Ressource verweist (eigene Übung, Kategorie, Plan, Quelltraining), wird erst gesendet, wenn diese bestätigt ist.
4. **Sichtbarer Sync-Zustand:** Ist dieses Gerät nicht Schreibgerät, erscheint ein Hinweisbanner mit „Übernehmen“. Unter Mehr steht „Zuletzt synchronisiert vor … · n ausstehend“.

### Non-Goals

- Keine gleichzeitigen Schreibgeräte; das Ein-Schreiber-Modell bleibt.
- Keine Backend-Änderung, sofern nicht zwingend nötig.

## Capabilities

- **Neu:** `sync-reliability`.

## Impact

- Flutter: `local_sync_store.dart` (Commit/Coalescing), `sync_repository.dart` (Push-Reihenfolge, Abhängigkeiten, Selbstheilung), Shell (Banner, Status), Tests.
