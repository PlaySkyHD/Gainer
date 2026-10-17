# Spec Delta

## Purpose

Diese Capability definiert den Lebenszyklus eines Trainings in der iPhone-App: Starten, aktive Session, Beenden, Bearbeiten und Löschen sowie die zugehörigen Trainingsmetadaten und die Zusammenfassung nach Abschluss.

## ADDED Requirements

### Requirement: Leeres Training starten

Das System MUST online wie offline ein leeres Training mit stabiler ID, auf Sekunden gerundeter Startzeit, ohne Endzeit und ohne Übungsblöcke anlegen können. Der Titel SHALL vorbelegt werden und bleibt editierbar.

#### Scenario: Leeres Training offline starten
- **GIVEN** das Gerät ist offline und es existiert kein aktives Training
- **WHEN** der Nutzer „Leeres Training“ wählt
- **THEN** wird sofort lokal ein Training mit stabiler ID, aktueller Startzeit und leerer Übungsliste angelegt und für die Synchronisation vorgemerkt

#### Scenario: Speicherfehler beim Start
- **GIVEN** das lokale Speichern schlägt fehl
- **WHEN** der Nutzer ein Training startet
- **THEN** zeigt die App einen Fehler, es entsteht kein halb angelegtes Training und kein Outbox-Eintrag

### Requirement: Training wiederholen

Der Nutzer SHALL ein früheres Training als Vorlage für ein neues Training verwenden können. Das neue Training übernimmt Titel, Übungsblöcke, Reihenfolge, Superset-Zuordnung und Satztypen, aber keine Satzwerte. Vor dem Start wählt der Nutzer die Vorwertquelle.

#### Scenario: Training wiederholen
- **GIVEN** ein früheres Training „Push“ mit Bankdrücken (1 Aufwärmsatz, 3 normale Sätze)
- **WHEN** der Nutzer „Training wiederholen“ mit der Vorwertquelle „dieses Training“ startet
- **THEN** entsteht ein neues aktives Training „Push“ mit vier leeren Bankdrück-Sätzen gleicher Typen, deren Platzhalter die Werte des früheren Trainings zeigen

#### Scenario: Wiederholtes Training später gelöscht
- **GIVEN** ein Training wurde aus Training X wiederholt
- **WHEN** Training X gelöscht wird
- **THEN** bleibt das neue Training vollständig erhalten und seine Vorwerte fallen auf die Quelle „nach Übung“ zurück

### Requirement: Genau ein aktives Training

Ein Training ohne Endzeit SHALL als aktiv gelten, unabhängig vom Kalendertag. Das System MUST höchstens ein aktives Training pro Nutzer zulassen und beim Versuch eines zweiten Starts das bestehende anbieten.

#### Scenario: Zweites Training starten
- **GIVEN** ein Training ohne Endzeit existiert
- **WHEN** der Nutzer ein weiteres Training starten möchte
- **THEN** bietet die App an, das aktive Training fortzusetzen oder es zuerst zu beenden, und legt kein zweites aktives Training an

#### Scenario: Training über Mitternacht
- **GIVEN** ein um 23:30 gestartetes Training ohne Endzeit
- **WHEN** der Nutzer die App um 00:15 öffnet
- **THEN** wird dasselbe Training weiterhin als aktiv mit fortlaufender Trainingszeit angezeigt

### Requirement: Aktive Session minimieren statt pausieren

Eine aktive Session MUST keine Pausenfunktion besitzen. Der Nutzer SHALL sie minimieren können; die App zeigt dann eine kompakte Leiste mit Trainingszeit seit Start, über die das Training wieder geöffnet wird.

#### Scenario: Minimieren und andere Bereiche nutzen
- **GIVEN** ein aktives Training ist geöffnet
- **WHEN** der Nutzer es minimiert und ein historisches Training ansieht
- **THEN** bleibt das aktive Training unverändert aktiv, die kompakte Leiste zeigt die weiterlaufende Trainingszeit und ein Tipp darauf öffnet es wieder

#### Scenario: App-Neustart während aktiver Session
- **GIVEN** ein aktives Training ist lokal gespeichert
- **WHEN** die App beendet und neu gestartet wird
- **THEN** wird das Training mit seinem zuletzt gespeicherten Stand und der aus der Startzeit berechneten Trainingszeit wiederhergestellt

### Requirement: Training beenden mit Fehlwerte-Dialog

Beim Beenden MUST das System prüfen, ob Sätze fehlende Pflichtwerte haben. Gibt es solche Sätze, SHALL ein Dialog die Optionen „Vorwerte übernehmen“, „Trotzdem beenden“ und „Weitertrainieren“ anbieten. Ohne fehlende Werte wird direkt beendet.

#### Scenario: Vorwerte übernehmen
- **GIVEN** ein Satz ohne Wiederholungen und mit vorhandenem Vorwert 100 kg × 8
- **WHEN** der Nutzer beendet und „Vorwerte übernehmen“ wählt
- **THEN** werden nur die leeren Felder mit 100 kg beziehungsweise 8 gefüllt, bereits eingetragene Werte bleiben unverändert und die Endzeit wird gesetzt

#### Scenario: Vorwert fehlt bei Übernahme
- **GIVEN** ein leerer Satz ohne passenden Vorwert
- **WHEN** der Nutzer „Vorwerte übernehmen“ wählt
- **THEN** bleiben dessen Felder leer und es wird weder 0 noch ein geschätzter Wert eingesetzt

#### Scenario: Trotzdem beenden
- **GIVEN** Sätze mit fehlenden Werten
- **WHEN** der Nutzer „Trotzdem beenden“ wählt
- **THEN** wird die Endzeit gesetzt und die fehlenden Werte bleiben leer

#### Scenario: Weitertrainieren
- **GIVEN** der Fehlwerte-Dialog ist offen
- **WHEN** der Nutzer „Weitertrainieren“ wählt
- **THEN** bleibt das Training ohne Endzeit aktiv und unverändert

### Requirement: Trainingszusammenfassung

Nach dem Beenden SHALL die App eine Zusammenfassung mit Dauer, Anzahl erfasster Sätze, Wiederholungen, Volumen und dem besten Satz je Übung anzeigen und neu erreichte persönliche Rekorde hervorheben.

#### Scenario: Zusammenfassung nach Abschluss
- **GIVEN** ein Training mit einem erfassten Satz 20 kg × 6 einer Kraftübung ohne Körpergewichtsanteil
- **WHEN** der Nutzer das Training beendet
- **THEN** zeigt die Zusammenfassung 1 Satz, 6 Wiederholungen, 120 kg Volumen und 20 kg × 6 als besten Satz

### Requirement: Trainingsmetadaten

Ein Training SHALL Titel, Trainingsnotiz sowie Start- und Endzeit besitzen, die jederzeit bearbeitet werden können. Die Endzeit MUST nach der Startzeit liegen. Ein Training speichert kein eigenes Körpergewicht; maßgeblich ist das Körpergewicht aus den täglichen Check-ins (siehe `training-statistics`).

#### Scenario: Ungültige Endzeit
- **GIVEN** ein abgeschlossenes Training mit Start 18:00
- **WHEN** der Nutzer die Endzeit auf 17:30 setzt
- **THEN** wird die Änderung mit einem Feldfehler abgelehnt und der vorherige Stand bleibt erhalten

#### Scenario: Kein Körpergewichtsfeld im Training
- **GIVEN** ein aktives oder historisches Training
- **WHEN** der Nutzer den Trainingskopf öffnet
- **THEN** zeigt er Titel, Startzeit, Endzeit und Notiz, aber kein Eingabefeld für das Körpergewicht

### Requirement: Historische Trainings bearbeiten

Das System MUST abgeschlossene Trainings im Tagebuch genauso bearbeitbar machen wie aktive: Metadaten, Übungsblöcke und Sätze. Änderungen SHALL Vorwerte, Kennzahlen und Rekorde bei der nächsten Berechnung beeinflussen.

#### Scenario: Satz in abgeschlossenem Training ändern
- **GIVEN** ein abgeschlossenes Training mit dem Satz 100 kg × 8
- **WHEN** der Nutzer ihn auf 100 kg × 10 ändert
- **THEN** wird die Änderung lokal gespeichert, synchronisiert und der Übungsverlauf zeigt 100 kg × 10

#### Scenario: Stammdatenänderung wirkt nicht rückwirkend
- **GIVEN** ein abgeschlossenes Training mit der Übung „Bankdrücken“ und dem Plan „Push“
- **WHEN** der Nutzer später die Übung umbenennt oder den Plan ändert
- **THEN** zeigt das historische Training weiterhin den gespeicherten Übungsnamen und seine eigenen Blöcke und Sätze

### Requirement: Training löschen

Der Nutzer SHALL jedes eigene Training nach Bestätigung löschen können. Ein gelöschtes Training MUST sofort aus Tagebuch, Vorwerten, Kennzahlen, Rekorden und Rotationsfortschritt verschwinden und als Löschung synchronisiert werden.

#### Scenario: Training offline löschen
- **GIVEN** ein abgeschlossenes Training und keine Netzverbindung
- **WHEN** der Nutzer das Löschen bestätigt
- **THEN** verschwindet es sofort aus dem Tagebuch und die Löschung wird nach Wiederverbindung genau einmal synchronisiert

#### Scenario: Aktives Training löschen
- **GIVEN** ein aktives Training mit erfassten Sätzen
- **WHEN** der Nutzer es löscht
- **THEN** existiert danach kein aktives Training mehr und Pausentimer sowie Live Activity werden beendet

### Requirement: Tagebuch

Die App SHALL alle nicht gelöschten Trainings im Tagebuch nach Startzeit absteigend, gruppiert nach Monat mit Anzahl der Trainings, anzeigen. Jeder Eintrag zeigt Datum, Titel, Dauer und die Übungen mit Satzanzahl.

#### Scenario: Monatsgruppen
- **GIVEN** zwei Trainings im Oktober und eines im September
- **WHEN** der Nutzer das Tagebuch öffnet
- **THEN** erscheinen die Oktober-Trainings neuestes zuerst unter „Oktober“ mit Anzahl 2, danach September mit Anzahl 1

### Requirement: Nutzerisolierte Trainings

Das System MUST Trainings, Übungsblöcke und Sätze ausschließlich dem authentifizierten Nutzer zuordnen und Zugriffe auf fremde Trainings-IDs ohne Datenoffenlegung ablehnen.

#### Scenario: Fremdes Training adressieren
- **GIVEN** Nutzer A kennt die Trainings-ID von Nutzer B
- **WHEN** Nutzer A diese ID in einer Sync-Mutation zum Bearbeiten oder Löschen verwendet
- **THEN** lehnt das Backend die Mutation ohne Offenlegung von Inhalten ab und das Training von B bleibt unverändert

#### Scenario: Wiederholte Sync-Mutation
- **GIVEN** eine Trainingsänderung wurde bereits erfolgreich verarbeitet
- **WHEN** der Client sie nach einem Netzwerkabbruch mit derselben Mutations-ID erneut sendet
- **THEN** antwortet das Backend mit dem bereits gespeicherten Ergebnis und es entsteht keine doppelte Wirkung
