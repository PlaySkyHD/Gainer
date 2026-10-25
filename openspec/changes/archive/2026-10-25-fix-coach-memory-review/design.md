# Design

## D1 `baseVersion` optional

`PUT /coach/memories/{id}` bekommt einen eigenen Request-Typ mit optionalem `baseVersion`. Die aktuelle App schickt es immer. Ältere TestFlight-Builds kennen das Feld nicht; wäre es Pflicht, scheiterte bei ihnen jedes Bearbeiten mit 400. Ohne Feld bleibt die Änderung deshalb ungeprüft wie bisher. Die Prüfung läuft unter der bestehenden Advisory-Sperre je Nutzer, zwei gleichzeitige Änderungen mit derselben Basisversion werden also sicher getrennt. Nicht gefundene Einträge antworten weiter vor der Versionsprüfung mit 404, damit fremde IDs nichts über ihre Version verraten.

## D2 Gleicher Text beim Anlegen

Der Nutzer entscheidet zuletzt: Eine andere Kategorie wird übernommen, `Version` und `UpdatedAtUtc` steigen, `CreatedAtUtc` bleibt. Die Liste sortiert nach `CreatedAtUtc`, der Eintrag bleibt also an seiner Stelle; die App ersetzt ihn dort, statt ihn nach oben zu holen.

## D3 Export

`coachMemories` ist ein eigener Abschnitt neben `resources`, weil das Gedächtnis kein Sync-Ressourcentyp ist und keinen Eintrag im Änderungs-Feed hat. Es wird in derselben `RepeatableRead`-Transaktion gelesen wie die Ressourcen. Das Feld ist neu und optional, `schemaVersion` bleibt 1: Leser, die es nicht kennen, verlieren nichts, und ein Import existiert noch nicht.

## D4 Prompt-Text

Die Notizen werden mit `JavaScriptEncoder.UnsafeRelaxedJsonEscaping` serialisiert, nur für dieses Eingabe-Element. Der Text landet nie in HTML. Das Budget von 4.000 Zeichen misst das komplette Element mit Kennzeichnung, IDs und JSON, so wie es gesendet wird.

## D5 Unbekannte Kategorie in der App

Ein Eintrag mit unbekannter Kategorie (etwa von einem neueren Server) erscheint unter „Sonstiges“, statt ausgelassen zu werden. Der Coach liest den Eintrag, also muss der Nutzer ihn sehen und löschen können. Bearbeitet er ihn, speichert die App die gewählte bekannte Kategorie.

## D6 Ein Längenmaß

Server (`string.Length`) und App (`String.length`) zählen UTF-16-Einheiten. Die App ersetzt den Grapheme zählenden `LengthLimitingTextInputFormatter` durch einen Formatter, der in UTF-16-Einheiten begrenzt und dabei kein Zeichen teilt. Zähler, Speichern-Prüfung und API-Client nutzen dieselbe Funktion.
