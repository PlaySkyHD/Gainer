# ai-meal-estimation Specification

## Purpose
Nutzerinitiierte KI-Schätzung von Mahlzeiten aus Freitext, Diktat und optional einem Foto. Ergebnisse sind Entwürfe und werden erst nach Prüfung als Einträge oder Gerichtsbestandteile übernommen.

## Requirements

### Requirement: Bewusst ausgelöste Freitext- und Fotoanalyse

Die Anwendung MUST eine AI-Schätzung aus einem begrenzten Freitext und optional genau einem unterstützten Bild erst nach ausdrücklicher Nutzeraktion auslösen. Eine reine Freitextanalyse MUST ohne Bild möglich sein. Bildtyp, Dateigröße und Abmessungen MUST vor der Weitergabe validiert werden; ein ungültiges Bild DARF nicht an den Provider gesendet werden.

#### Scenario: Freitext schätzen lassen

- **GIVEN** ein angemeldeter Nutzer beschreibt eine Mahlzeit mit „250 g Skyr, Banane und 30 g Haferflocken“
- **WHEN** er die Schätzung ausdrücklich startet
- **THEN** erhält er einen strukturierten Entwurf mit getrennten Komponenten und es wird noch kein Ernährungseintrag gespeichert

#### Scenario: Bild überschreitet die Grenze

- **GIVEN** ein ausgewähltes Bild überschreitet eine erlaubte Größen- oder Abmessungsgrenze
- **WHEN** der Nutzer die Fotoanalyse startet
- **THEN** lehnt die Anwendung den Upload mit einer verständlichen Meldung ab und sendet weder Bild noch Freitext an OpenAI

#### Scenario: Analyse ist offline nicht verfügbar

- **GIVEN** das Gerät besitzt keine Netzwerkverbindung
- **WHEN** der Nutzer eine AI-Schätzung starten möchte
- **THEN** kennzeichnet die Anwendung die Funktion als online erforderlich und lässt manuelle, zuletzt verwendete sowie lokal gespeicherte Gerichte weiterhin zu

### Requirement: Informierte und datensparsame Fotoverarbeitung

Vor dem ersten Foto-Upload MUST die App Zweck, Empfänger und Schätzcharakter anzeigen und eine aktive Bestätigung verlangen. Das System MUST nicht benötigte Bildmetadaten entfernen und OpenAI-Requests mit `store=false` senden. Originalbild, Freitext und Providerantwort DÜRFEN nicht in Application-Logs, Traces oder Metrics gelangen. Temporäre Bilddaten MUST nach Abschluss oder Fehler verworfen werden und DÜRFEN weder in PostgreSQL noch in Blob Storage verbleiben.

#### Scenario: Erster Foto-Upload

- **GIVEN** ein Nutzer hat noch keiner Fotoanalyse zugestimmt
- **WHEN** er erstmals ein Mahlzeitenfoto analysieren lassen möchte
- **THEN** zeigt die Anwendung vor der Übermittlung den Datenschutzhinweis und startet ohne seine Bestätigung keinen Providerrequest

#### Scenario: Analyse wurde beendet

- **GIVEN** ein Bild wurde für eine Schätzung temporär verarbeitet
- **WHEN** der Provider erfolgreich antwortet oder der Request fehlschlägt
- **THEN** werden die temporären Bildbytes verworfen und normale Telemetrie enthält weder Bildinhalt noch Freitext noch strukturierte Providerantwort

### Requirement: Strukturierter und validierter Schätzentwurf

Eine erfolgreiche Analyse MUST einen serverseitig gegen ein festes Schema validierten Entwurf mit mindestens einer Komponente liefern. Jede Komponente MUST Name, geschätzte Menge und Kilokalorien sowie optional Makros enthalten; fehlende Werte DÜRFEN nicht als 0 g erscheinen. Schätzcharakter, Unsicherheiten und Datenlücken MUST sichtbar sein. Nicht schemafähige, nicht endliche, negative oder außerhalb fachlicher Grenzen liegende Werte MUST abgelehnt werden.

#### Scenario: Mehrere Komponenten erkannt

- **GIVEN** der Provider erkennt Reis, Hähnchen und Sauce mit plausiblen Werten
- **WHEN** die Antwort das interne Schema und alle fachlichen Grenzen erfüllt
- **THEN** zeigt die Anwendung drei getrennt bearbeitbare Komponenten mit Schätzhinweis und vorhandenen Unsicherheiten an

#### Scenario: Makro konnte nicht geschätzt werden

- **GIVEN** der Provider kann den Fettwert einer Sauce nicht verlässlich bestimmen
- **WHEN** der Entwurf angezeigt wird
- **THEN** bleibt Fett für diese Komponente als fehlend beziehungsweise unsicher markiert und wird nicht als 0 g dargestellt

#### Scenario: Providerantwort ist ungültig

- **GIVEN** der Provider liefert Freitext statt des Schemas oder ungültige Zahlen
- **WHEN** das Backend die Antwort validiert
- **THEN** verwirft es den Entwurf vollständig, speichert keine Ernährungseinträge und bietet Retry oder manuelle Erfassung an

### Requirement: Prüfung und Bestätigung vor der Übernahme

AI-Ergebnisse MUST Entwürfe bleiben und DÜRFEN weder Ernährungstage noch Gerichte oder Ziele automatisch verändern. Der Nutzer MUST jede Komponente bearbeiten, entfernen oder ergänzen und das Speicherziel prüfen können; aus einem Ernährungstag sind das Tag und Mahlzeit. Erst seine Bestätigung SHALL die ausgewählten Komponenten mit neuen stabilen IDs atomar übernehmen. Übernommene Snapshots MUST ihre Herkunft als bestätigte AI-Schätzung kennzeichnen.

#### Scenario: Entwurf korrigieren und übernehmen

- **GIVEN** ein Entwurf schätzt 200 g Reis und der Nutzer korrigiert ihn auf 150 g
- **WHEN** er die ausgewählten Komponenten für Mittagessen bestätigt
- **THEN** werden die korrigierten Werte als einzelne unabhängige Einträge gespeichert und die ursprüngliche Schätzung wird nicht zusätzlich erfasst

#### Scenario: Bestätigung kann nicht atomar gespeichert werden

- **GIVEN** ein Entwurf enthält drei ausgewählte Komponenten
- **WHEN** das lokale Speichern von Ernährungstag und Outbox-Mutation fehlschlägt
- **THEN** erscheint keine der drei Komponenten als erfolgreich gespeichert und der bearbeitete Entwurf bleibt für einen erneuten Versuch verfügbar

#### Scenario: Entwurf verwerfen

- **GIVEN** ein AI-Entwurf wird angezeigt
- **WHEN** der Nutzer ihn verwirft
- **THEN** entstehen keine Fach- oder Sync-Daten und die temporären Eingaben werden entfernt

### Requirement: Übernahme in einen Gerichtsentwurf

Ist die Schätzung aus einem Gerichtseditor geöffnet, SHALL die Bestätigung die ausgewählten Komponenten in den lokalen Gerichtsentwurf übernehmen. Sie DARF keinen Ernährungstag anlegen oder verändern; Fach- und Sync-Daten entstehen erst, wenn der Nutzer das Gericht speichert.

#### Scenario: Entwurf in ein wiederverwendbares Gericht übernehmen

- **GIVEN** eine AI-Schätzung wurde aus einem Gerichtseditor geöffnet und enthält mehrere geprüfte Komponenten
- **WHEN** der Nutzer die ausgewählten Komponenten bestätigt
- **THEN** werden sie als getrennte Komponenten in den lokalen Gerichtsentwurf übernommen, ohne einen Ernährungstag anzulegen oder zu verändern, und erst das spätere Speichern des Gerichts erzeugt dessen Fach- und Sync-Daten

### Requirement: Eingeschränkter AI-Kontext und Nutzerisolation

Die Analyse MUST serverseitig an die authentifizierte Sitzung gebunden sein. Der Provider DARF keinen direkten Datenbankzugriff, keine frei wählbare Nutzer-ID, keine mutierenden Tools und keine Daten anderer Nutzer erhalten. Freitext und Bildinhalt MUST als nicht vertrauenswürdige Eingaben behandelt werden; darin enthaltene Anweisungen DÜRFEN weder Systemregeln verändern noch weitere Daten oder Tools freigeben.

#### Scenario: Bild enthält eine Anweisung

- **GIVEN** ein Mahlzeitenfoto oder sein Begleittext enthält eine Aufforderung, andere Nutzerdaten abzurufen
- **WHEN** die Analyse ausgeführt wird
- **THEN** bleibt die Ausgabe auf das feste Nährwertschema beschränkt und es wird kein Daten- oder Toolzugriff ausgelöst

#### Scenario: Manipulierte Nutzer-ID

- **GIVEN** ein Client sendet zusammen mit der Analyse eine fremde Nutzer-ID
- **WHEN** das Backend den Request verarbeitet
- **THEN** ignoriert beziehungsweise verwirft es die fremde Zuordnung und bindet Rate-Limit und Verarbeitung ausschließlich an die authentifizierte Identität

### Requirement: Begrenzung und kontrollierte Providerfehler

Die Anwendung MUST Analyse-Requests pro Nutzer begrenzen und MUST Timeout, Rate-Limit, Kostenlimit, Inhaltsablehnung und Providerausfall auf stabile Fehlerzustände abbilden. Ein Retry DARF nicht selbständig Ernährungseinträge anlegen, und ein Providerfehler DARF die sonstige Ernährungserfassung nicht blockieren.

#### Scenario: Provider ist vorübergehend nicht verfügbar

- **GIVEN** OpenAI antwortet mit einem temporären Fehler oder Timeout
- **WHEN** eine Schätzung angefordert wird
- **THEN** zeigt die Anwendung einen wiederholbaren Fehler ohne Teilentwurf und lässt manuelle Erfassung sowie Gerichte weiter verwenden

#### Scenario: Nutzerbudget ist erschöpft

- **GIVEN** ein Nutzer hat das konfigurierte Analysebudget erreicht
- **WHEN** er eine weitere Analyse startet
- **THEN** lehnt das Backend sie vor einem Providerrequest mit einem stabilen Hinweis ab und verändert keine Ernährungsdaten

### Requirement: Referenzwerte per Websuche

Die Mahlzeiten-Schätzung SHALL Nährwerte pro 100 g aus Nährwertdatenbanken ansetzen und dafür per Websuche auf einer konfigurierten Liste von Nährwertseiten nachschlagen können. Grundzutaten SHALL als roh gelten, solange keine Zubereitung genannt ist. Eine Quelle MUST nur angezeigt werden, wenn sie ein https-Link auf einer erlaubten Seite ist. Lehnt der Anbieter die Suche ab, SHALL die Schätzung ohne Suche erfolgen statt zu scheitern.

#### Scenario: Hähnchenbrustfilet
- **GIVEN** die Beschreibung „200 g Hähnchenbrustfilet“
- **WHEN** die KI schätzt
- **THEN** liegt das Fett im Bereich roher Hähnchenbrust (etwa 1–2 g pro 100 g), und der Vorschlag zeigt die Quelle, z. B. „fddb.info“

#### Scenario: Fremde Quelle
- **GIVEN** das Modell nennt eine Seite außerhalb der Liste
- **WHEN** der Server die Antwort prüft
- **THEN** entfällt die Quelle, und die Werte bleiben als Vorschlag erhalten

#### Scenario: Suche nicht verfügbar
- **GIVEN** der Anbieter lehnt die Anfrage mit Websuche mit HTTP 400 ab
- **WHEN** die Schätzung läuft
- **THEN** wiederholt der Server sie einmal ohne Suche und liefert einen Vorschlag

### Requirement: Salz in der Mahlzeiten-Schätzung

Die KI-Schätzung SHALL Salz je Bestandteil nur angeben, wenn es von Haus aus im Essen steckt (z. B. Brot, Käse, Pizza, Döner). Für schlichte oder selbstgekochte Zutaten MUST sie kein Salz angeben, und Salz, das beim Kochen dazukommt, MUST NOT geschätzt werden. Nennt die Beschreibung eine Salzmenge, SHALL daraus ein eigener Bestandteil „Salz“ mit 0 kcal werden.

#### Scenario: Pizza
- **GIVEN** die Beschreibung „Pizza Margherita“
- **WHEN** die KI schätzt
- **THEN** zeigt der Vorschlag z. B. „350 g · 890 kcal · ~3,5 g Salz · mittel“

#### Scenario: Selbst gekocht und gesalzen
- **GIVEN** die Beschreibung „Hähnchen mit Reis, selbst gesalzen“
- **WHEN** die KI schätzt
- **THEN** haben Hähnchen und Reis kein Salz, und der Vorschlag bietet „Selbst gesalzen? Salz hinzufügen“ an

#### Scenario: Genannte Menge
- **GIVEN** die Beschreibung „Reis mit einem Teelöffel Salz“
- **WHEN** die KI schätzt
- **THEN** enthält der Vorschlag den Bestandteil „Salz“ mit 6 g und 0 kcal

### Requirement: Bestandteile einzeln übernehmen

Übernimmt der Nutzer einen Bestandteil, SHALL nur dieser aus dem Vorschlag verschwinden. Die übrigen MUST zum Prüfen stehen bleiben.

#### Scenario: Zwei Bestandteile
- **GIVEN** ein Vorschlag mit „Pizza Margherita“ und „Reis“
- **WHEN** der Nutzer „Pizza Margherita“ übernimmt
- **THEN** steht „Reis“ weiterhin im Vorschlag

### Requirement: Mahlzeit diktieren

Das Sheet „Mahlzeit schätzen“ SHALL einen Button „Diktieren“ anbieten, der die Beschreibung per Spracherkennung auf dem Gerät füllt. Audio MUST NOT das Gerät verlassen. Der erkannte Text SHALL live im Feld erscheinen und an vorhandenen Text angehängt werden. Die Schätzung MUST erst auf „Mahlzeit schätzen“ starten.

#### Scenario: Diktat füllt die Beschreibung
- **GIVEN** das Sheet „Mahlzeit schätzen“ ist offen
- **WHEN** der Nutzer „Diktieren“ tippt und „Zwei Eier und ein Toast“ sagt
- **THEN** steht der Text im Feld „Beschreibung“ und der Button heißt „Fertig“

#### Scenario: Schätzen während der Aufnahme
- **GIVEN** ein laufendes Diktat
- **WHEN** der Nutzer „Mahlzeit schätzen“ tippt
- **THEN** endet die Aufnahme und die Schätzung nutzt den endgültigen Text

### Requirement: Rechte und Verfügbarkeit

Lehnt der Nutzer Mikrofon oder Spracherkennung ab oder fehlt die Erkennung auf dem Gerät, SHALL die App einen Hinweis mit dem Weg in die Einstellungen zeigen und MUST NOT aufnehmen. Ohne Diktat-Plattform MUST der Button fehlen.

#### Scenario: Rechte abgelehnt
- **GIVEN** die Spracherkennung ist in den Einstellungen nicht erlaubt
- **WHEN** der Nutzer „Diktieren“ tippt
- **THEN** zeigt das Sheet „Erlaube Mikrofon und Spracherkennung in den iOS-Einstellungen, um zu diktieren.“
