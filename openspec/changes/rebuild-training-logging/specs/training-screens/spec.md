# Spec Delta

## Purpose

Diese Capability definiert Aufbau und Bedienung der Trainings-Screens der iPhone-App: Tagebuch, aktives und historisches Training, Satzzeilen, Zahleneingabe, Timeransichten, Übungsauswahl, Pläne, Zusammenfassung und Live Activity.

## ADDED Requirements

### Requirement: Tagebuchansicht

Das Tagebuch SHALL unter einem großen Titel je Monat eine Kopfzeile mit Monat links und Trainingsanzahl rechts zeigen. Jedes Training ist eine Zeile in einer Monatskarte mit Datums-Badge (Wochentag klein, Tag groß) links, Titel und Dauer in Minuten rechts sowie darunter je Übung „<Satzanzahl>x <Übungsname>“. Oben stehen „Bearbeiten“ und „+“.

#### Scenario: Trainingszeile
- **GIVEN** ein Training „Legs 2“ am Donnerstag, 15. Oktober, mit 129 Minuten Dauer, 2 Sätzen Beinbeuger und 3 Sätzen Beinstrecker
- **WHEN** das Tagebuch angezeigt wird
- **THEN** zeigt die Zeile „Do 15“, „Legs 2“, „129 min“, „2x Beinbeuger“ und „3x Beinstrecker“

#### Scenario: Wischen zum Löschen
- **GIVEN** eine Trainingszeile im Tagebuch
- **WHEN** der Nutzer sie nach links wischt
- **THEN** erscheint eine rote Löschaktion, die erst nach Bestätigung löscht

### Requirement: Kopf des Trainingsscreens

Ein aktives Training SHALL oben links einen Minimieren-Button, daneben die Akzent-Pille „Beenden“, mittig das Datum und rechts eine gemeinsame Pille mit Timer- und Menü-Button zeigen. Ein historisches Training zeigt statt Minimieren/Beenden einen runden Akzent-Haken zum Schließen.

#### Scenario: Historisches Training öffnen
- **GIVEN** ein abgeschlossenes Training vom 15. Oktober
- **WHEN** der Nutzer es im Tagebuch öffnet
- **THEN** zeigt der Kopf einen runden türkisen Haken, „15. Okt.“ und die Timer-/Menü-Pille, aber keine „Beenden“-Pille

### Requirement: Metadatenkarte

Oberhalb der Übungen SHALL eine Karte mit dem Trainingstitel als Überschrift sowie Zeilen „Startzeit“, „Endzeit“ (Werte rechts in Sekundärtext) und „Notizen“ mit Pfeil stehen. Antippen einer Zeit öffnet einen Datums-/Zeitwähler.

#### Scenario: Startzeit ändern
- **GIVEN** die Metadatenkarte eines Trainings
- **WHEN** der Nutzer „Startzeit“ antippt und eine neue Zeit wählt
- **THEN** zeigt die Zeile den neuen Wert und die Trainingsdauer im Tagebuch passt sich an

### Requirement: Übungskarte

Jeder Übungsblock SHALL eine Karte sein mit Übungsname (fett), darunter der Übungsnotiz in kleinem Sekundärtext, rechts einem „…“-Menü, den Satzzeilen und einer Fußzeile mit „+ Satz hinzufügen“ links sowie Icon-Buttons für Verlauf, Graph und Rekorde rechts. Supersets werden als zusammenhängende Karte mit Buchstabenkennung A/B dargestellt.

#### Scenario: Fußzeilenaktionen
- **GIVEN** eine Übungskarte „Beinbeuger“
- **WHEN** der Nutzer das Rekord-Icon antippt
- **THEN** öffnen sich die persönlichen Rekorde von „Beinbeuger“ in einem Sheet

### Requirement: Satzzeile

Eine Satzzeile SHALL links das Satzlabel in einem Kreis (Nummer, W oder D), dann die Spalten mit kleinen grauen Labels „Kg“, „Wdh.“ und „Notizen“ über den Werten sowie rechts ein „…“-Menü zeigen. Spalten richten sich nach dem Übungstyp. Platzhalter-Vorwerte erscheinen deutlich blasser als eingetragene Werte.

#### Scenario: Zeile mit Vorwert und Eintrag
- **GIVEN** Satz 1 ist mit 20 kg × 6 eingetragen, Satz 2 zeigt den Vorwert 15 × 7
- **WHEN** die Übungskarte angezeigt wird
- **THEN** erscheinen 20 und 6 in Primärtext, 15 und 7 deutlich blasser, und beide Zeilen tragen die Labels Kg, Wdh. und Notizen

#### Scenario: Reines Körpergewicht
- **GIVEN** eine Übung vom Typ reines Körpergewicht
- **WHEN** ihre Satzzeile angezeigt wird
- **THEN** fehlt die Spalte „Kg“ und „Wdh.“ rückt nach links

### Requirement: Zahleneingabe mit Navigationsleiste

Beim Fokus auf ein Zahlenfeld SHALL über der Ziffernblock-Tastatur eine Leiste mit „zurück“, „weiter“ und „fertig“ sowie einem Button zum Ausblenden der Tastatur erscheinen. „Weiter“ springt von Kg zu Wdh. und von Wdh. zum Kg-Feld des nächsten Satzes. Darüber bleibt die kompakte Timerleiste sichtbar.

#### Scenario: Durch Sätze navigieren
- **GIVEN** das Wdh.-Feld von Satz 1 ist fokussiert und 6 ist eingetragen
- **WHEN** der Nutzer „weiter“ tippt
- **THEN** wird das Kg-Feld von Satz 2 fokussiert und der Wert 6 ist gespeichert

### Requirement: Kompakte und große Timeransicht

Die kompakte Timerleiste SHALL am unteren Rand mit Griff, Start/Stopp-Button links, Countdown mittig und Schließen rechts liegen; der Stopp-Zustand ist orange. Hochziehen oder Antippen öffnet die große Ansicht mit Ring-Fortschritt, großem Countdown, „−15s“, rundem Start/Stopp-Button, „+15s“ und einer Reihe runder Shortcut-Buttons mit „+“ zum Anlegen.

#### Scenario: Große Ansicht öffnen
- **GIVEN** die kompakte Leiste zeigt 03:00 im Bereit-Zustand
- **WHEN** der Nutzer die Leiste nach oben zieht
- **THEN** erscheint die große Ansicht mit vollem Ring, 03:00, türkisem Start-Button sowie Shortcuts 01:00, 02:00, 03:00 und „+“

#### Scenario: Laufender Timer
- **GIVEN** die große Ansicht mit laufendem Timer
- **WHEN** Zeit vergeht
- **THEN** nimmt der Ring proportional ab und der zentrale Button ist orange mit Stopp-Symbol

### Requirement: Übungsauswahl

Die Übungsauswahl SHALL als Sheet mit „Abbrechen“, Titel, „+“ (neue Übung) und „…“ oben, einem Suchfeld und einer Kategorienliste mit Pfeilen erscheinen. Unten steht ein Umschalter „Normal | Supersatz“; im Supersatz-Modus sind mehrere Übungen markierbar.

#### Scenario: Supersatz wählen
- **GIVEN** die Übungsauswahl im Modus „Supersatz“
- **WHEN** der Nutzer in der Kategorie „Bizeps“ und „Trizeps“ je eine Übung markiert und bestätigt
- **THEN** werden beide Übungen als Superset hinzugefügt

### Requirement: Fehlwerte-Dialog und Zusammenfassung

Der Fehlwerte-Dialog SHALL den Titel „Gewicht oder Wiederholungen fehlen“, eine Erklärung und die gestapelten Aktionen „Ja, Vorwerte verwenden“, „Trotzdem beenden“, „Weitertrainieren“ zeigen. Die Zusammenfassung zeigt eine Illustration, einen motivierenden Titel, „Dein n. Training · m. diese Woche“, eine Karte mit Volumen, Sätzen, Wiederholungen und bestem Satz je Übung sowie „Training fortsetzen“.

#### Scenario: Zusammenfassung
- **GIVEN** das 248. Training des Nutzers, das 4. in dieser Woche, wurde gerade beendet
- **WHEN** die Zusammenfassung erscheint
- **THEN** zeigt sie „Dein 248. Training · 4. diese Woche“ und über „Training fortsetzen“ kann das Training wieder geöffnet werden, wobei die Endzeit entfernt wird

### Requirement: Plan- und Wiederholen-Ansichten

Der Planeditor SHALL einen großen Titel, darunter eine Karte „Training beginnen“, eine Karte mit Name, Vorwertquelle und Notizen, je eine Karte pro Eintrag mit Satzanzahl und „+ Übung hinzufügen“ zeigen. „Training wiederholen“ ist ein Sheet mit „Training beginnen“ und den drei erklärten Vorwertquellen mit Haken an der gewählten.

#### Scenario: Vorwertquelle beim Wiederholen
- **GIVEN** das Sheet „Training wiederholen“ für ein Training vom 9. Oktober
- **WHEN** der Nutzer „Wiederholtes Training“ wählt und „Training beginnen“ tippt
- **THEN** startet ein neues Training, dessen Platzhalter die Werte vom 9. Oktober zeigen

### Requirement: Live-Activity-Layout

Die Live Activity SHALL auf dem Sperrbildschirm eine dunkle Karte mit App-Icon und Trainingstitel links oben, verstrichener Zeit rechts oben und mittig groß dem aktuellen Übungsnamen mit „Satz x von y“ zeigen; bei laufender Pause steht darüber ein großer Countdown und darunter weiterhin Übung und nächster Satz. Ohne Details zeigt die Karte statt der Übung groß die Trainingszeit; sie ist nie leer.

#### Scenario: Pause mit Übung
- **GIVEN** Details aktiv, Training „Legs 2“, Beinbeuger mit zwei Sätzen, der erste erfasst, Pause läuft mit 0:32
- **WHEN** das iPhone gesperrt ist
- **THEN** zeigt die Karte den Countdown 0:32 groß und darunter „Beinbeuger - Sitzen“ und „Satz 2 von 2“

#### Scenario: Sperrbildschirm mit Details
- **GIVEN** Detailfreigabe aktiv, Training „Legs 2“, Übung „Beinbeuger - Sitzen“, erster von zwei Sätzen, kein Timer
- **WHEN** das iPhone gesperrt ist
- **THEN** zeigt die Karte „Legs 2“, die Trainingszeit, „Beinbeuger - Sitzen“ und „Satz 1 von 2“
