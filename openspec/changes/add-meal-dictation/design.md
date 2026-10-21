# Design

## D1 Nur auf dem Gerät

`SFSpeechAudioBufferRecognitionRequest` läuft mit `requiresOnDeviceRecognition = true` und `addsPunctuation = true`. Ist die Erkennung auf dem Gerät für `de-DE` nicht verfügbar, meldet die App „nicht verfügbar“ und weist auf die Diktier-Einstellung hin. Auf die Server-Erkennung von Apple wird nicht ausgewichen.

## D2 Abfrage statt Ereignisstrom

Wie beim Pulsgurt fragt Dart den Stand ab (`readDictation`, alle 150 ms). Zurück kommen Zustand und Text. Die Zustände sind `idle`, `listening`, `finished`, `denied`, `unavailable` und `failed`. Ein Generationszähler im nativen Teil verwirft Ergebnisse eines abgebrochenen Diktats.

## D3 Audio

Die Audiosession läuft während der Aufnahme mit `.record` und `.measurement` und wird danach mit `notifyOthersOnDeactivation` freigegeben. Der Tap auf den Eingangsknoten und der Ergebnis-Handler entstehen in `nonisolated`-Funktionen, weil sie auf fremden Threads laufen. Ergebnisse gehen per `Task { @MainActor … }` zurück.

## D4 Oberfläche

- Den Button gibt es nur, wenn eine `DictationPlatform` vorhanden ist.
- Während der Aufnahme sagt die Fußzeile „Ich höre zu …“. Hinweise zu Rechten, Verfügbarkeit oder fehlender Erkennung ersetzen die Fußzeile.
- „Mahlzeit schätzen“ wartet höchstens 2 s auf den endgültigen Text.
- Beim Schließen des Sheets bricht `dispose` das Diktat ab.
