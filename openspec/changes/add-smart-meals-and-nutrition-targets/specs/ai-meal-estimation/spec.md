## Purpose

Diese Capability ermöglicht eine nutzerinitiierte Schätzung von Mahlzeiten aus Freitext und optional einem Foto, deren unsichere Ergebnisse erst nach sichtbarer Prüfung als einzelne Ernährungseinträge oder Komponenten eines wiederverwendbaren Gerichts übernommen werden.

## ADDED Requirements

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

Die Anwendung MUST vor dem ersten Foto-Upload Zweck und Empfänger der Übermittlung sowie den Schätzcharakter des Ergebnisses verständlich anzeigen und eine aktive Bestätigung verlangen. Das System MUST nicht benötigte Bildmetadaten entfernen, MUST OpenAI-Requests mit deaktivierter Response-Speicherung senden und DARF Originalbild, Freitext oder Providerantwort nicht in normalen Application-Logs, Traces oder Metrics speichern. Temporäre Bilddaten MUST nach Abschluss oder Fehler verworfen werden und DÜRFEN standardmäßig weder in PostgreSQL noch in Blob Storage verbleiben.

#### Scenario: Erster Foto-Upload

- **GIVEN** ein Nutzer hat noch keiner Fotoanalyse zugestimmt
- **WHEN** er erstmals ein Mahlzeitenfoto analysieren lassen möchte
- **THEN** zeigt die Anwendung vor der Übermittlung den Datenschutzhinweis und startet ohne seine Bestätigung keinen Providerrequest

#### Scenario: Analyse wurde beendet

- **GIVEN** ein Bild wurde für eine Schätzung temporär verarbeitet
- **WHEN** der Provider erfolgreich antwortet oder der Request fehlschlägt
- **THEN** werden die temporären Bildbytes verworfen und normale Telemetrie enthält weder Bildinhalt noch Freitext noch strukturierte Providerantwort

### Requirement: Strukturierter und validierter Schätzentwurf

Eine erfolgreiche Analyse MUST einen serverseitig gegen ein festes Schema validierten Entwurf mit mindestens einer Komponente liefern. Jede Komponente MUST einen Namen, eine geschätzte Menge, Kilokalorien sowie optional Protein, Kohlenhydrate und Fett enthalten; fehlende Werte DÜRFEN nicht als null Gramm ausgegeben werden. Der Entwurf MUST Schätzcharakter, Unsicherheiten und Datenlücken sichtbar kennzeichnen. Nicht schemafähige, nicht endliche, negative oder außerhalb fachlicher Grenzen liegende Werte MUST abgelehnt werden.

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

AI-Ergebnisse MUST reine Entwürfe bleiben und DÜRFEN weder Ernährungstage noch Gerichte oder Ziele automatisch verändern. Der Nutzer MUST jede Komponente bearbeiten, entfernen oder ergänzen und vor der Übernahme das vom aufrufenden Kontext bestimmte Speicherziel prüfen können. Bei Aufruf aus einem Ernährungstag umfasst dieses Ziel Tag und Mahlzeit; bei Aufruf aus einem Gerichtseditor ist es der aktuelle lokale Gerichtsentwurf. Erst seine ausdrückliche Bestätigung SHALL die ausgewählten Komponenten mit neuen stabilen IDs atomar in dieses Ziel übernehmen. Nutrition-Entry- und Reusable-Meal-Component-Snapshots MUST ihre Herkunft als bestätigte AI-Schätzung kennzeichnen. Die Übernahme in einen Gerichtsentwurf DARF keinen Ernährungstag anlegen oder verändern und persistiert erst mit dem ausdrücklichen Speichern des Gerichts Fach- und Sync-Daten.

#### Scenario: Entwurf korrigieren und übernehmen

- **GIVEN** ein Entwurf schätzt 200 g Reis und der Nutzer korrigiert ihn auf 150 g
- **WHEN** er die ausgewählten Komponenten für Mittagessen bestätigt
- **THEN** werden die korrigierten Werte als einzelne unabhängige Einträge gespeichert und die ursprüngliche Schätzung wird nicht zusätzlich erfasst

#### Scenario: Bestätigung kann nicht atomar gespeichert werden

- **GIVEN** ein Entwurf enthält drei ausgewählte Komponenten
- **WHEN** das lokale Speichern von Ernährungstag und Outbox-Mutation fehlschlägt
- **THEN** erscheint keine der drei Komponenten als erfolgreich gespeichert und der bearbeitete Entwurf bleibt für einen erneuten Versuch verfügbar

#### Scenario: Entwurf in ein wiederverwendbares Gericht übernehmen

- **GIVEN** eine AI-Schätzung wurde aus einem Gerichtseditor geöffnet und enthält mehrere geprüfte Komponenten
- **WHEN** der Nutzer die ausgewählten Komponenten bestätigt
- **THEN** werden sie als getrennte Komponenten in den lokalen Gerichtsentwurf übernommen, ohne einen Ernährungstag anzulegen oder zu verändern, und erst das spätere Speichern des Gerichts erzeugt dessen Fach- und Sync-Daten

#### Scenario: Entwurf verwerfen

- **GIVEN** ein AI-Entwurf wird angezeigt
- **WHEN** der Nutzer ihn verwirft
- **THEN** entstehen keine Fach- oder Sync-Daten und die temporären Eingaben werden entfernt

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
