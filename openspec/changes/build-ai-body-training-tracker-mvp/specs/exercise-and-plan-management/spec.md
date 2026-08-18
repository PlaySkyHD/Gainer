## Purpose

Diese Capability definiert den stabilen Übungskatalog, wiederverwendbare Trainingsvorlagen und eine einfache nutzergebundene Workout-Rotation für die MVP-Kernreise.

## ADDED Requirements

### Requirement: Übungskatalog mit stabilen Identitäten

Das System MUST einen nur lesbaren Basiskatalog und nutzereigene Übungen mit jeweils stabiler Übungs-ID bereitstellen. Es SHALL Basiseinträge anhand von Name, Zielmuskel, Muskelgruppe und Equipment auffindbar machen, ohne für den MVP lizenzpflichtige Bilder oder Animationen vorauszusetzen.

#### Scenario: Basisübung suchen

- **GIVEN** der Basiskatalog enthält eine Übung mit stabiler ID und den passenden Metadaten
- **WHEN** ein Nutzer nach ihrem Namen sucht oder nach Muskelgruppe beziehungsweise Equipment filtert
- **THEN** wird die Übung mit derselben stabilen ID in den Treffern angezeigt

#### Scenario: Basiskatalog verändern

- **GIVEN** ein Nutzer kennt die ID einer Basisübung
- **WHEN** er versucht, diesen Basiseintrag zu bearbeiten oder zu archivieren
- **THEN** wird die Änderung abgelehnt und der Basiseintrag bleibt unverändert

### Requirement: Nutzereigene Übungen

Das System SHALL einem Nutzer erlauben, eigene Übungen mit einem Namen und optionalen Beschreibungs-, Muskel- und Equipmentdaten anzulegen, zu bearbeiten und zu archivieren. Eigene Übungen MUST ausschließlich für ihren Eigentümer sichtbar und veränderbar sein.

#### Scenario: Eigene Übung anlegen

- **GIVEN** ein authentifizierter Nutzer gibt einen gültigen Namen ein
- **WHEN** er eine eigene Übung speichert
- **THEN** wird eine stabile Übungs-ID erzeugt und die Übung ausschließlich seinem Katalog hinzugefügt

#### Scenario: Referenzierte Übung archivieren

- **GIVEN** eine eigene Übung wird von einem Template oder historischen Workout referenziert
- **WHEN** der Eigentümer die Übung archiviert
- **THEN** wird sie nicht mehr für neue Template-Einträge angeboten und bleibt in bestehenden Referenzen auflösbar

#### Scenario: Fremde eigene Übung adressieren

- **GIVEN** Nutzer A kennt die ID einer eigenen Übung von Nutzer B
- **WHEN** Nutzer A versucht, sie zu lesen oder zu verändern
- **THEN** wird der Zugriff ohne Offenlegung ihrer Daten abgelehnt und keine Änderung gespeichert

### Requirement: Wiederverwendbare Trainingsvorlagen

Das System MUST nutzergebundene Trainingsvorlagen mit Namen und einer geordneten Liste von Übungen verwalten. Pro Template-Übung SHALL es eine positive Satzanzahl, einen positiven Wiederholungsbereich, optionales RIR zwischen 0 und 10, optionale nicht negative Pausenzeit und Notizen speichern.

#### Scenario: Gültiges Template speichern

- **GIVEN** ein Nutzer hat mindestens eine für ihn verfügbare Übung ausgewählt
- **WHEN** er einen Namen, gültige Satz- und Wiederholungsvorgaben sowie optionale gültige Werte speichert
- **THEN** wird das Template mit stabiler ID und der gewählten Übungsreihenfolge ausschließlich für ihn gespeichert

#### Scenario: Ungültige Planvorgabe ablehnen

- **GIVEN** ein Template-Eintrag enthält null Sätze oder eine obere Wiederholungsgrenze unterhalb der unteren
- **WHEN** der Nutzer das Template speichert
- **THEN** wird das Speichern mit feldbezogenen Fehlern abgelehnt und der zuvor gültige Stand bleibt unverändert

#### Scenario: Fremdes Template adressieren

- **GIVEN** Nutzer A kennt die Template-ID von Nutzer B
- **WHEN** Nutzer A diese ID für eine Lese- oder Schreiboperation verwendet
- **THEN** wird die Operation ohne Offenlegung oder Änderung fremder Inhalte abgelehnt

### Requirement: Template-Änderungen ohne Rückwirkung

Das System MUST Änderungen an Übungen und Templates von bereits gestarteten oder abgeschlossenen Workouts trennen. Eine Template-Änderung SHALL ausschließlich zukünftige Starts beeinflussen und darf ein laufendes oder historisches Workout nicht verändern.

#### Scenario: Template nach abgeschlossenem Workout ändern

- **GIVEN** ein Workout wurde aus einem Template gestartet und abgeschlossen
- **WHEN** der Nutzer Übungen, Reihenfolge, Vorgaben oder Namen im Template ändert
- **THEN** zeigt das abgeschlossene Workout weiterhin exakt seinen gespeicherten Snapshot

#### Scenario: Laufendes Workout anpassen

- **GIVEN** ein Nutzer verändert Übungen oder Sätze nur innerhalb eines laufenden Workouts
- **WHEN** er das Workout speichert oder abschließt
- **THEN** bleibt das zugrunde liegende Template ohne eine separate ausdrückliche Template-Aktion unverändert

### Requirement: Einfache Workout-Rotation

Das System MUST pro Nutzer eine explizit geordnete Rotation aktiver Templates und das daraus folgende nächste Template verwalten. Nach Abschluss eines Rotations-Templates SHALL dessen aktiver Nachfolger vorgeschlagen werden; nach dem letzten folgt wieder das erste. Archivierte oder entfernte Templates MUST übersprungen werden.

#### Scenario: Nächstes Template fortschreiben

- **GIVEN** die Rotation lautet „Push A“, „Pull A“, „Legs A“ und „Push A“ wurde zuletzt abgeschlossen
- **WHEN** die Anwendung den nächsten Trainingsvorschlag ermittelt
- **THEN** schlägt sie „Pull A“ vor

#### Scenario: Rotation umlaufen

- **GIVEN** das letzte aktive Template der Rotation wurde abgeschlossen
- **WHEN** der nächste Trainingsvorschlag ermittelt wird
- **THEN** schlägt die Anwendung das erste aktive Template vor

#### Scenario: Leere Rotation

- **GIVEN** ein Nutzer hat keine aktiven Templates in seiner Rotation
- **WHEN** der nächste Trainingsvorschlag abgefragt wird
- **THEN** zeigt die Anwendung einen leeren Zustand und schlägt kein fremdes oder archiviertes Template vor
