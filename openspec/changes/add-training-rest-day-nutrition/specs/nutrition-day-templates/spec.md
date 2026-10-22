# nutrition-day-templates

## Purpose

Nutzer mit festem Ernährungsplan speichern einen ganzen Ernährungstag als benannte Vorlage. Sie können sie überschreiben und auf andere Tage anwenden, ohne Einträge einzeln neu zu erfassen.

## ADDED Requirements

### Requirement: Tag als Vorlage speichern

Der Nutzer SHALL einen Ernährungstag mit mindestens einem Eintrag über „Tag als Vorlage speichern“ als neue Vorlage speichern können. Dafür gibt er einen Namen mit 1–80 Zeichen an und wählt optional die Tagesart „Trainingstag“ oder „Ruhetag“. Die Vorlage MUST alle Einträge des Tages mit Mahlzeit, Reihenfolge, Menge, Stückangaben, Nährwerten und Quelle enthalten. An einem Tag ohne Einträge MUST die Aktion deaktiviert sein.

#### Scenario: Neue Vorlage
- **GIVEN** heute enthält Frühstück mit Haferflocken 80 g und Mittag mit Reis 150 g und Hähnchen 200 g
- **WHEN** der Nutzer „Tag als Vorlage speichern“ wählt, „Trainingstag“ als Namen eingibt, die Tagesart „Trainingstag“ wählt und speichert
- **THEN** gibt es die Vorlage „Trainingstag“ mit 3 Einträgen in denselben Mahlzeiten und Mengen

#### Scenario: Leerer Tag
- **GIVEN** der geöffnete Tag hat keine Einträge
- **WHEN** der Nutzer das Tagesmenü öffnet
- **THEN** ist „Tag als Vorlage speichern“ deaktiviert

### Requirement: Vorlage überschreiben

Im selben Sheet SHALL der Nutzer statt einer neuen Vorlage eine bestehende auswählen und mit dem Inhalt des Tages überschreiben können. Vorher MUST die App nachfragen: „„<Name>“ überschreiben?“. Name und Tagesart der Vorlage bleiben erhalten, alle Einträge werden durch die des Tages ersetzt.

#### Scenario: Plan angepasst
- **GIVEN** die Vorlage „Ruhetag“ mit 5 Einträgen, und heute enthält 6 Einträge
- **WHEN** der Nutzer „Ruhetag“ auswählt und „Überschreiben“ bestätigt
- **THEN** enthält „Ruhetag“ genau die 6 Einträge von heute

### Requirement: Vorlage anwenden

Der Nutzer SHALL über „Aus Vorlage befüllen“ eine Vorlage auf den geöffneten Tag anwenden können, auch auf vergangene und künftige Tage. Hat der Tag keine Einträge, MUST die App die Einträge direkt übernehmen. Hat er schon welche, MUST die App fragen:
- **„Ersetzen“** entfernt alle Einträge des Tages und übernimmt die der Vorlage.
- **„Hinzufügen“** hängt die Einträge der Vorlage in ihren Mahlzeiten hinten an.
- **„Abbrechen“** ändert nichts.

#### Scenario: Leerer Tag
- **GIVEN** morgen hat keine Einträge
- **WHEN** der Nutzer für morgen die Vorlage „Trainingstag“ anwendet
- **THEN** hat morgen die 3 Einträge der Vorlage in denselben Mahlzeiten

#### Scenario: Ersetzen
- **GIVEN** heute enthält 2 Einträge
- **WHEN** der Nutzer „Trainingstag“ anwendet und „Ersetzen“ wählt
- **THEN** enthält heute genau die 3 Einträge der Vorlage

#### Scenario: Hinzufügen
- **GIVEN** heute enthält beim Frühstück einen Kaffee
- **WHEN** der Nutzer „Trainingstag“ anwendet und „Hinzufügen“ wählt
- **THEN** enthält das Frühstück den Kaffee und danach die Haferflocken, und der Tag hat 4 Einträge

### Requirement: Übernommene Einträge

Übernommene Einträge MUST unabhängige Kopien mit neuen IDs sein. Eine manuelle Tagesart des Tages MUST erhalten bleiben. Hätte der Tag danach mehr als 200 Einträge, MUST die App das Anwenden ablehnen und den Grund nennen.

#### Scenario: Vorlage später geändert
- **GIVEN** die Vorlage „Trainingstag“ wurde gestern angewendet
- **WHEN** der Nutzer die Vorlage heute überschreibt
- **THEN** bleiben die Einträge von gestern unverändert

#### Scenario: Zu viele Einträge
- **GIVEN** heute hat 190 Einträge und die Vorlage hat 15
- **WHEN** der Nutzer „Hinzufügen“ wählt
- **THEN** ändert die App nichts und meldet, dass ein Tag höchstens 200 Einträge haben kann

### Requirement: Vorschlag passend zur Tagesart

Ist der geöffnete Tag heute oder künftig und hat er keine Einträge, SHALL die Tageskarte einen Vorschlag zeigen: „Vorlage „<Name>“ übernehmen“. Voraussetzung ist eine Vorlage, deren Tagesart der Tagesart des Tages entspricht. Passen mehrere, MUST die zuletzt geänderte vorgeschlagen werden. Ein Tipp MUST die Vorlage anwenden. Der Vorschlag MUST auch ohne Ruhetag-Ziel erscheinen, weil sich die Tagesart immer bestimmen lässt. Vorlagen ohne Tagesart werden nie vorgeschlagen.

#### Scenario: Ruhetag
- **GIVEN** morgen ist laut Rhythmus Ruhetag, hat keine Einträge, und es gibt die Vorlage „Ruhetag“ mit Tagesart Ruhetag
- **WHEN** der Nutzer morgen im Tab „Essen“ öffnet
- **THEN** zeigt die Tageskarte „Vorlage „Ruhetag“ übernehmen“

#### Scenario: Tag mit Einträgen
- **GIVEN** heute hat bereits einen Eintrag
- **WHEN** der Nutzer den Tab „Essen“ öffnet
- **THEN** zeigt die Tageskarte keinen Vorschlag

### Requirement: Vorlagen verwalten

Der Tab „Essen“ SHALL einen Bereich „Tagesvorlagen“ zeigen. Jede Vorlage erscheint mit Name, Tagesart sowie Summe aus kcal und Protein. Ein Tipp SHALL eine Ansicht der Einträge nach Mahlzeit öffnen, in der sich Name und Tagesart ändern lassen. Wischen nach links SHALL die Vorlage nach Bestätigung löschen. Das Löschen MUST NOT Tage ändern, auf die sie angewendet wurde. Ein Nutzer MUST höchstens 50 Vorlagen haben können.

#### Scenario: Löschen
- **GIVEN** die Vorlage „Ruhetag“ wurde auf 10 Tage angewendet
- **WHEN** der Nutzer sie löscht
- **THEN** ist sie aus der Liste verschwunden, und die 10 Tage behalten ihre Einträge

#### Scenario: Obergrenze
- **GIVEN** der Nutzer hat 50 Vorlagen
- **WHEN** er einen Tag als neue Vorlage speichern will
- **THEN** ist nur Überschreiben möglich, und die App erklärt die Obergrenze

### Requirement: Speichern, Offline und Synchronisation der Vorlagen

Vorlagen MUST offline angelegt, überschrieben, angewendet und gelöscht werden können. Sie MUST als eigene Ressource mit Versionsprüfung über den Sync-Vertrag laufen. Jede Mutation überträgt den vollständigen Stand. Dieselbe Mutation-ID MUST NOT doppelt angewendet werden. Das Anwenden ändert nur den Ernährungstag, nicht die Vorlage. Bei abgelaufener Sitzung MUST die Änderung in der Outbox bleiben.

#### Scenario: Offline speichern und anwenden
- **GIVEN** das Gerät ist offline
- **WHEN** der Nutzer heute als Vorlage „Trainingstag“ speichert und sie auf morgen anwendet
- **THEN** zeigt die App beides sofort, und nach Wiederverbindung hat der Server die Vorlage und den Tag von morgen

#### Scenario: Veralteter Stand
- **GIVEN** der Server hat die Vorlage in Version 3
- **WHEN** eine Mutation mit Basisversion 2 eintrifft
- **THEN** meldet der Server einen Konflikt, und die App bietet die bestehende Konfliktauflösung an

### Requirement: Serverseitige Prüfung und Isolation der Vorlagen

Der Server MUST eine Vorlagen-Mutation ablehnen, wenn eine dieser Bedingungen zutrifft:
- Name leer oder länger als 80 Zeichen
- mehr als 200 Einträge oder doppelte Eintrags-IDs
- ein Eintrag verletzt die Regeln für Ernährungseinträge
- Tagesart unbekannt
- es würden mehr als 50 Vorlagen entstehen

Vorlagen MUST nur für den angemeldeten Nutzer lesbar, änderbar und löschbar sein.

#### Scenario: Fremde Vorlage löschen
- **GIVEN** Nutzer A hat eine Vorlage
- **WHEN** Nutzer B eine Löschmutation mit deren ID sendet
- **THEN** antwortet der Server mit „nicht gefunden“, und die Vorlage von Nutzer A bleibt bestehen

#### Scenario: Zu viele Einträge
- **WHEN** eine Mutation eine Vorlage mit 201 Einträgen speichern will
- **THEN** antwortet der Server mit einem Validierungsfehler und speichert nichts
