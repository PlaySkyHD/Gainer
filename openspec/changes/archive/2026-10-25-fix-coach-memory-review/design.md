# Design

## D1 `baseVersion` optional

`PUT /coach/memories/{id}` bekommt einen eigenen Request-Typ mit optionalem `baseVersion`. Die aktuelle App schickt es immer. Ältere TestFlight-Builds kennen das Feld nicht; wäre es Pflicht, scheiterte bei ihnen jedes Bearbeiten mit 400. Ohne Feld bleibt die Änderung deshalb ungeprüft wie bisher. Die Prüfung läuft unter der bestehenden Advisory-Sperre je Nutzer, zwei gleichzeitige Änderungen mit derselben Basisversion werden also sicher getrennt. Nicht gefundene Einträge antworten weiter vor der Versionsprüfung mit 404, damit fremde IDs nichts über ihre Version verraten.

## D2 Gleicher Text beim Anlegen

Der Nutzer entscheidet zuletzt: Eine andere Kategorie wird übernommen, `Version` und `UpdatedAtUtc` steigen, `CreatedAtUtc` bleibt. Die Liste sortiert nach `CreatedAtUtc`, der Eintrag bleibt also an seiner Stelle; die App ersetzt ihn dort, statt ihn nach oben zu holen.

## D3 Export

`coachMemories` ist ein eigener Abschnitt neben `resources`, weil das Gedächtnis kein Sync-Ressourcentyp ist und keinen Eintrag im Änderungs-Feed hat. Es wird in derselben `RepeatableRead`-Transaktion gelesen wie die Ressourcen. Das Feld ist neu und optional, `schemaVersion` bleibt 1: Leser, die es nicht kennen, verlieren nichts, und ein Import existiert noch nicht.

## D4 Prompt-Text

Die Notizen werden mit `JavaScriptEncoder.UnsafeRelaxedJsonEscaping` serialisiert, nur für dieses Eingabe-Element. Der Text landet nie in HTML. Das Budget misst das komplette Element mit Kennzeichnung, IDs und JSON, so wie es gesendet wird. Es rechnet Text und Hülle getrennt: 50 × (200 Zeichen Text + 100 Zeichen Hülle) + 100 für Kennzeichnung = 15.100 Zeichen. Ein volles Gedächtnis passt also hinein; nur Texte mit vielen zu maskierenden Zeichen (Anführungszeichen, Backslash) verdrängen die ältesten Notizen. Jede Notiz wird einmal serialisiert, die Längen werden aufsummiert und der Text am Ende einmal gebaut.

## D5 Unbekannte Kategorie in der App

Ein Eintrag mit unbekannter Kategorie (etwa von einem neueren Server) erscheint unter „Sonstiges“, statt ausgelassen zu werden. Der Coach liest den Eintrag, also muss der Nutzer ihn sehen und löschen können. Die App führt den Wire-Wert mit und sendet ihn beim Bearbeiten unverändert zurück, solange der Nutzer die Kategorie nicht ändert.

## D6 Gelöschte Notiz beim Bearbeiten

Meldet der Server beim Ändern `memory_not_found`, bleibt das Sheet offen und wechselt auf „Neue Notiz“: Erneutes Sichern legt den Text neu an, statt noch einmal gegen die gelöschte ID zu senden. Schließen ohne Speichern bleibt möglich. Das Sheet einfach zu schließen hätte den getippten Text verworfen. Dass die Liste neu geladen ist, sagt die Meldung nur, wenn das Laden gelang.

## D7 Sheet während des Speicherns geschlossen

Das gemeinsame `showGainerSheet` lässt sich per X, Wischen und Tippen auf den Hintergrund schließen; es nur für dieses Sheet zu sperren, hätte die gemeinsame Komponente geändert. Stattdessen meldet der Screen einen Fehler über seine Fehlerzeile, wenn das Sheet beim Scheitern schon zu war.

## D8 Ein Längenmaß

Server (`string.Length`) und App (`String.length`) zählen UTF-16-Einheiten. Die App ersetzt den Grapheme zählenden `LengthLimitingTextInputFormatter` durch einen Formatter, der in UTF-16-Einheiten begrenzt und dabei kein Zeichen teilt. Wie `MaxLengthEnforcement.truncateAfterCompositionEnds` kürzt er erst nach einer IME-Komposition. Zähler, Speichern-Prüfung und API-Client nutzen dieselbe Funktion.
