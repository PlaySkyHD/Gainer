# Proposal

## Why

Nach einem Gerätewechsel oder längerer Offline-Zeit lehnt der Server alte, in der Warteschlange stehende Änderungen ab, etwa den Start eines Trainings („active_workout_exists“), weil inzwischen ein anderes Training aktiv war, oder ein Training, dessen Übung oder Plan auf dem Server noch fehlt („validation_failed“). Der lokale Stand ist meist längst weiter, die Trainings sind beendet oder gelöscht. „Lokale Änderung erneut senden“ schickt aber die alte Nutzlast und ist für diese Codes gesperrt, „Serverstand nutzen“ scheitert, wenn der Server die Ressource nie hatte. Der Nutzer kommt aus den Konflikten nicht heraus.

## What Changes

- **Lokalen Stand erzwingen:** Für einen Konflikt ersetzt die App alle wartenden Änderungen der betroffenen Ressource durch genau eine Änderung, die den aktuellen lokalen Stand überträgt: anlegen, wenn der Server sie nicht kennt; speichern gegen die aktuelle Serverversion; löschen, wenn sie lokal gelöscht ist; nichts senden und lokal entfernen, wenn sie lokal gelöscht ist und der Server sie nie hatte.
- **Mehrfachauswahl:** In der Konfliktliste lassen sich Konflikte auswählen („Auswählen“, „Alle auswählen“) und gemeinsam erzwingen oder mit dem Serverstand ersetzen. Erzwungen wird in der ursprünglichen Reihenfolge der Änderungen, danach startet ein Sync.
- **Verständliche Gründe:** Die Konfliktzeile nennt den Grund auf Deutsch (z. B. „Ein anderes Training war noch aktiv“, „Übung oder Plan fehlt auf dem Server“) und den Titel der Ressource statt nur der ID.
- „Serverstand nutzen“ wird nur angeboten, wenn ein Serverstand existiert.

### Non-Goals

- Keine Backend-Änderung; der Server prüft weiterhin alle Regeln.
- Kein automatisches Erzwingen ohne Nutzeraktion.

## Capabilities

- **Neu:** `sync-force-local`.

## Impact

- Flutter: `local_conflict_recovery.dart`, `sync_repository.dart`, `sync_view_model.dart`, `sync_screen.dart`, Tests.
