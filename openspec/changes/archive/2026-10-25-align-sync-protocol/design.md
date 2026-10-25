# Design

## Decisions

### D1 – Eine Protokollkonstante für alle Registrierungen

`nativeSyncProtocolVersion` liegt in `sync_protocol.dart`, nutzbar ohne Importzyklus. Sync und Geräteübergabe registrieren damit, und die Übergabe verlangt dieselbe Version in der Antwort. Die frühere Konstante `nativeHandoverSyncProtocolVersion = 3` entfällt. Ein App-Test prüft, dass Sync und Übergabe dieselbe Version senden. Ein Server-Test schließt eine Übergabe ab, nachdem das Konto Wasser erfasst hat.

### D2 – Angehaltene Einträge nur nach einem Update

Nach erfolgreicher Registrierung liest die App `registered-protocol-version` aus den Sync-Metadaten. Fehlt der Wert (ältere App) oder ist er kleiner als die aktuelle Version, setzt sie `upgradeRequired`-Einträge auf `pending` und speichert die aktuelle Version. Sonst bleiben die Einträge liegen. Lehnt der Server einen Push mit `upgrade_required` ab, sendet dieselbe App-Version ihn also nicht in jedem Lauf erneut.

### D3 – Sync-Status und Bericht

- `SyncStatus.upgradeRequired` wird nur zurückgesetzt, wenn ein Lauf den Server erreicht: `idle`, `synced`, `retryPending` oder `inactiveClient`. `authBlocked` und `busy` lassen den Hinweis stehen.
- Der Bericht zählt bei `upgrade_required` und bei unbekannten Typen die im laufenden Pull schon angewendeten Batches mit.

### D4 – Typisierte Speicherfehler

`LocalResourceChangedException` und `LocalWritesFrozenException` erben von `StateError`, damit bestehende Behandlungen weiter greifen. Das Wasser-Repository erkennt sie am Typ statt am Text und meldet auf Deutsch:
- „Die Wassermenge hat sich gerade beim Synchronisieren geändert. Bitte versuche es noch einmal.“ nach drei Versuchen,
- „Während der Geräteübergabe lässt sich nichts ändern …“ bei eingefrorenen Änderungen.

### D5 – Zweite ID für einen belegten Tag

Da alle Apps die ID aus Konto und Datum bilden, ist eine andere ID für einen belegten Tag ein fehlerhafter Client, kein veralteter Stand. Ein neuer Basisstand würde den Konflikt nicht lösen. Deshalb prüft der Handler den Tag vor dem Anlegen, und auch ein Unique-Fehler aus einem Wettrennen ergibt `water_day_exists` (422, Lessons Abschnitt 6).

### D6 – Tages-ID mit SHA-256

Die ID ist eine namensbasierte UUID v8 nach RFC 9562: die ersten 16 Byte von SHA-256 über Namensraum, Konto und Datum, Version-Nibble 8, Variante RFC 4122. SHA-1 entfällt. Ein Test hält einen unabhängig berechneten Wert fest, damit sich die Ableitung nicht unbemerkt ändert.

### D7 – Feed nur mit Protokoll

`ISyncChangeFeed.GetAsync` verlangt die Protokollversion. Der Weg ohne Filter entfällt, damit kein Aufrufer versehentlich unbekannte Typen ausliefert. Die Sync-Controller nutzen gemeinsam `SyncProblemResults.Create` für ProblemDetails mit `code`.
