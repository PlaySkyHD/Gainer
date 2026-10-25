# Design

## Decisions

### D1 – Eigene Sync-Ressource statt Feld an bestehender Ressource

Die Wassermenge eines Tages ist die neue Ressource `WaterIntakeDay` (`ResourceKind` 14) mit `Id`, `LocalDate`, `AmountMl`, `CreatedAtUtc`, `UpdatedAtUtc` und `Version`. Geprüfte Alternativen:

- **Feld am Ernährungstag (`NutritionDay`).** `saveNutritionDay` ersetzt bei jeder Änderung alle Einträge des Tages. Jeder Tipp auf „+300 ml“ würde den ganzen Tag neu schreiben und mit Bearbeitungen am Tagebuch um dieselbe Version konkurrieren. Außerdem entstünden Ernährungstage ohne Einträge, nur weil Wasser erfasst wurde. Für Analytics zählt aber gerade, ob ein Tag Einträge hat.
- **Feld am Check-in (`DailyCheckIn`).** Ein Check-in verlangt ein Gewicht größer 0. Wasser ohne Wiegen wäre nicht möglich.

Die eigene Ressource hat eine kleine Nutzlast und eigene Versionen. Sie stört weder Tagebuch noch Check-in. Weil der Datenexport (#109) den neuesten Stand jeder Ressource aus dem Change-Feed liest, erscheint Wasser dort ohne weitere Änderung.

Eindeutig ist `(UserId, LocalDate)`. Die ID vergibt die App zufällig, wie beim Ernährungstag, und findet den Tag lokal über das Datum. Schickt ein Client für denselben Tag eine zweite ID, gilt das wie beim Check-in als Konflikt (`stale_base_version`), denn auf dem Server liegt dann wirklich ein anderer Stand.

### D2 – Zwei Mutationen mit Basisversion

- `addWaterIntake` mit `waterIntakeDayId`, `localDate`, `baseVersion`, `amountMl`: addiert 1 bis 10.000 ml.
- `setWaterIntake` mit denselben Feldern: setzt die Tagesmenge auf 0 bis 10.000 ml.

Beide legen den Tag an, wenn die Basisversion 0 ist und er fehlt. Andernfalls verlangen beide die passende Version und erhöhen sie um 1. Ein fehlender Tag bei Basisversion größer 0 ergibt `resource_not_found`, eine abweichende Version `stale_base_version`.

Die App nutzt `addWaterIntake` nur, wenn für den Tag keine Änderung wartet, also die Arbeitskopie dem Serverstand entspricht. Sonst sendet sie `setWaterIntake` mit der neuen Summe. Grund ist die Outbox: Sie fasst eine noch nicht gesendete Änderung derselben Ressource mit der neuen zusammen und behält nur den neuesten Body (offline-sync, „Ein wartender Stand je Ressource“). Eine zusammengefasste Differenz würde frühere Tipps verlieren. Eine Summe bleibt richtig. Der Body trägt deshalb immer die Summe `amountMl` und bei einer Addition zusätzlich `addedMl`. Der Codec wählt die Operation danach, ob `addedMl` gesetzt ist.

Lese- und Schreibvorgang einer Änderung laufen in der App nacheinander durch eine Warteschlange. Zwei schnelle Tipps lesen sonst denselben Stand, und einer ginge verloren.

### D3 – Grenzen

Die Tagesmenge liegt zwischen 0 und 10.000 ml, als ganze Zahl. Eine Addition muss mindestens 1 ml betragen und darf die Grenze nicht überschreiten. Die Datenbank sichert die Spanne zusätzlich mit einem Check-Constraint. Verstöße meldet der Server als `invalid_payload`. Die App bietet keinen Schnellknopf an, der die Grenze überschreiten würde, und prüft die Eingabe im Sheet.

### D4 – Keine Löschung

Ein Tag mit 0 ml bleibt als Stand bestehen. „Zurücksetzen“ setzt 0 ml. Es gibt daher keine Löschmarke und kein Neuanlegen unter derselben ID, wofür App und Server sonst Sonderfälle brauchen (`_recreatableAggregateTypes`). Der Export enthält den Tag dann mit 0 ml, was dem tatsächlichen Stand entspricht.

### D5 – Server

`WaterIntakeDay : UserOwnedEntity` in `Gainer.Core.Nutrition`, Tabelle `tracking.water_intake_days` mit eindeutigem Index `(UserId, LocalDate)`, Check-Constraint `AmountMl BETWEEN 0 AND 10000`, `Version` als Concurrency-Token und Cascade auf den Nutzer. Der globale Query-Filter isoliert die Nutzer. `WaterIntakeMutationHandler` folgt dem Muster der übrigen Handler und meldet `WaterIntakeConflictException` bzw. `WaterIntakeNotFoundException`. `SyncMutationProcessor` übersetzt sie in `stale_base_version` bzw. `resource_not_found`. Der Snapshot `WaterIntakeDaySnapshot` enthält `waterIntakeDayId`, `localDate`, `amountMl`, Zeitstempel und `version`.

`DatabaseSchemaVersion.RequiredMigration` zeigt auf die neue Migration `AddWaterTracking`, damit die API erst nach der Migration bereit ist.

### D6 – App: Sync

Lokaler Typ `water-intake-day`, Servertyp `WaterIntakeDay`. Die Arbeitskopie enthält `localDate`, `amountMl`, `createdAtUtc` und `updatedAtUtc`. Der Typ zählt zu den Ressourcen, deren Body der Arbeitskopie entspricht. Ausnahme ist `addedMl`, das ein erzwungener lokaler Stand nicht braucht, weil er als Summe gesendet wird. Damit gelten Zusammenfassen, Selbstheilung und „Lokalen Stand erzwingen“ wie beim Ernährungstag. Die Konfliktliste zeigt „Wasser“ und das Datum. Eingehende Snapshots verlieren `version` und `waterIntakeDayId`, wie bei den übrigen Ernährungsressourcen.

### D7 – App: Einstellungen

`NutritionPreferences` speichert `waterEnabled` (Standard aus) und `waterGoalMl` (Standard 2.500, erlaubt 250 bis 10.000) unter dem Schlüssel `nutritionPreferences` in den Sync-Metadaten der Kontodatenbank. Das ist dasselbe Muster wie bei `trainingPreferences` und `cardioPreferences`: gerätelokal, an das Konto gebunden, keine Sync-Mutation. Ausschalten blendet nur die Karte aus; erfasste Mengen bleiben erhalten und werden weiter synchronisiert.

Die Einstellungen öffnet der neue Menüpunkt „Einstellungen“ im Menü (…) der Ernährung als eigener Screen über `pushSingleInstance`. Er enthält den Schalter „Wasser erfassen“ und, solange er an ist, das Feld „Tagesziel“ in ml.

### D8 – App: Karte und Sheet

Die Karte steht direkt unter der Tageskarte und besteht aus Bausteinen aus `lib/ui/core/components`:

- eine Zeile „Wasser“ mit dem Wert „1.250 / 2.500 ml“ und Pfeil; Antippen öffnet das Sheet. Bei großer Schrift steht der Wert unter dem Titel, sonst bricht „Wasser“ mitten im Wort um,
- ein `GainerProgressBar` ohne Warnfarbe, denn mehr Wasser als das Ziel ist kein Fehler,
- drei `GainerPillButton` (tonal) „+200 ml“, „+300 ml“, „+500 ml“ in gleich breiten Spalten. Der neue Parameter `compact` verringert den Innenabstand, damit die Beschriftung in eine Zeile passt. Bei Textgröße 2 stehen die Knöpfe in einem `Wrap` und brechen um statt überzulaufen.

Zahlen nutzen `formatNutritionNumber` (Tausenderpunkt). Ein Knopf, der die Grenze überschreiten würde, ist deaktiviert. Das Sheet (`showGainerSheet`) heißt „Wasser“ und hat „Sichern“ im Kopf. Es enthält ein Feld „Tagesmenge“ mit Einheit ml und darunter „Auf 0 ml zurücksetzen“. Ein ungültiger Wert zeigt einen Fehler am Feld und speichert nichts.

## Risks / Trade-offs

- Wer auf zwei Geräten abwechselnd erfasst, bekommt wie überall sonst einen sichtbaren Konflikt statt einer Addition. Das ist das bestehende Einzelschreiber-Modell.
- Das Tagesziel ist gerätelokal. Nach einem Gerätewechsel gilt wieder der Standard von 2.500 ml und die Karte ist ausgeblendet, bis der Nutzer sie einschaltet. Die Mengen selbst bleiben erhalten.
