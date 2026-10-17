# Spec Delta

## Purpose

Diese Capability definiert den manuell gesteuerten Pausentimer eines aktiven Trainings und die gemeinsame Darstellung von Trainingszeit und Pause in der App, auf dem Sperrbildschirm und in der Dynamic Island.

## ADDED Requirements

### Requirement: Pausentimer nur manuell starten

Ein Pausentimer MUST ausschließlich durch eine bewusste Nutzeraktion starten. Das Erfassen eines Satzes, das Öffnen der Timeransicht oder das Ablaufen eines vorherigen Timers DÜRFEN keinen Timer starten.

#### Scenario: Satz erfasst ohne Timeraktion
- **GIVEN** ein aktives Training ohne laufenden Timer
- **WHEN** der Nutzer einen Satz vollständig einträgt
- **THEN** startet kein Pausentimer

#### Scenario: Timeransicht öffnen
- **GIVEN** der Timer ist auf 3:00 eingestellt
- **WHEN** der Nutzer die Timeransicht öffnet
- **THEN** zeigt sie 3:00 im Bereit-Zustand und läuft erst nach Tippen auf Start

### Requirement: Dauer wählen und Shortcuts

Der Nutzer SHALL die Dauer zwischen 5 Sekunden und 30 Minuten frei einstellen, vor und während des Laufs um ±15 Sekunden ändern sowie eigene Dauer-Shortcuts anlegen, auswählen und löschen können. Shortcuts werden pro Konto auf dem Gerät gespeichert; Standard sind 1:00, 2:00 und 3:00.

#### Scenario: Shortcut verwenden
- **GIVEN** ein eigener Shortcut 2:30
- **WHEN** der Nutzer ihn wählt und Start tippt
- **THEN** läuft ein Timer mit 2:30

#### Scenario: Laufzeit verlängern
- **GIVEN** ein laufender Timer mit 0:40 Restzeit
- **WHEN** der Nutzer +15 s tippt
- **THEN** beträgt die Restzeit 0:55 und Live Activity sowie Benachrichtigung werden auf das neue Ende aktualisiert

### Requirement: Stop pausiert, Start setzt fort

Stop MUST einen laufenden Timer mit erhaltener Restzeit anhalten; Start setzt ihn mit dieser Restzeit fort. Die Trainingszeit läuft dabei unverändert weiter.

#### Scenario: Pausieren und fortsetzen
- **GIVEN** ein laufender Timer mit 1:10 Restzeit
- **WHEN** der Nutzer Stop tippt, 30 Sekunden wartet und dann Start tippt
- **THEN** läuft der Timer mit 1:10 weiter und die Trainingszeit ist um die 30 Sekunden gewachsen

### Requirement: Schließen setzt zurück

Schließen (X) MUST den Timer beenden und die Timeransicht schließen. Beim erneuten Öffnen SHALL die zuletzt gestartete Ausgangsdauer im Bereit-Zustand bereitstehen, nicht die alte Restzeit.

#### Scenario: Nach X erneut öffnen
- **GIVEN** ein auf 3:00 gestarteter Timer mit 1:00 Restzeit
- **WHEN** der Nutzer X tippt und die Timeransicht später erneut öffnet
- **THEN** stehen 3:00 im Bereit-Zustand bereit und eine eventuell geplante Ablaufbenachrichtigung ist entfernt

### Requirement: Ablauf signalisieren

Beim Ablauf SHALL die App eine lokale Benachrichtigung „Pause vorbei“ mit Ton zeigen – im Hintergrund, auf dem Sperrbildschirm und auch bei geöffneter App –, sofern Benachrichtigungen erlaubt sind; bei geöffneter App zusätzlich eine Haptik. Ohne Berechtigung MUST die geöffnete App ersatzweise einen kurzen Ton abspielen. Die Anzeige MUST 0:00 zeigen, bis der nächste Satz vollständig erfasst ist oder der Nutzer den Timer schließt; negative Restzeiten DÜRFEN nicht erscheinen.

#### Scenario: Ablauf im Vordergrund
- **GIVEN** ein laufender Timer, Benachrichtigungen sind erlaubt und die App ist geöffnet
- **WHEN** die Restzeit 0 erreicht
- **THEN** erscheint die Benachrichtigung „Pause vorbei“ als Banner mit Ton, das Gerät gibt eine Haptik, es ertönt kein zweiter Ton aus der App, die Anzeige bleibt auf 0:00 und es startet kein neuer Timer

#### Scenario: Ablauf im Hintergrund
- **GIVEN** ein laufender Timer, Benachrichtigungen sind erlaubt und die App ist im Hintergrund oder das iPhone gesperrt
- **WHEN** die Restzeit 0 erreicht
- **THEN** erscheint die Benachrichtigung „Pause vorbei“ mit Ton, auch wenn die App nicht ausgeführt wird

#### Scenario: Benachrichtigung entfällt nach Stop oder Schließen
- **GIVEN** ein laufender Timer mit geplanter Benachrichtigung
- **WHEN** der Nutzer Stop oder X tippt, das Training beendet oder löscht oder das Konto wechselt
- **THEN** wird die geplante Benachrichtigung entfernt und erscheint später nicht

#### Scenario: Rückkehr zur Trainingszeit
- **GIVEN** ein abgelaufener Timer mit Anzeige 0:00
- **WHEN** der Nutzer im nächsten Kraftsatz zunächst nur das Gewicht und dann die Wiederholungen einträgt
- **THEN** bleibt die Anzeige nach dem Gewicht auf 0:00 und wechselt erst nach den Wiederholungen zur Trainingszeit

#### Scenario: Benachrichtigungen verweigert
- **GIVEN** der Nutzer hat Benachrichtigungen verweigert
- **WHEN** ein Timer bei geöffneter App abläuft
- **THEN** spielt die App einen kurzen Ton und eine Haptik ab, das Training wird nicht blockiert und bei späterem Öffnen aus dem Hintergrund zeigt die App den abgelaufenen Zustand

### Requirement: Eine Timerwahrheit

Timerzustand (Ausgangsdauer, Zielzeitpunkt oder pausierte Restzeit) MUST lokal pro Training gespeichert werden. App, Live Activity und Benachrichtigung SHALL denselben Zustand verwenden; die Restzeit wird immer aus dem Zielzeitpunkt berechnet.

#### Scenario: Rückkehr aus dem Hintergrund
- **GIVEN** ein 3:00-Timer läuft und die App geht in den Hintergrund
- **WHEN** der Nutzer nach etwa 30 Sekunden zurückkehrt
- **THEN** zeigt die App etwa 2:30 und nicht 3:00

#### Scenario: Prozessende während der Pause
- **GIVEN** ein laufender Timer und die App wird vom System beendet
- **WHEN** der Nutzer die App neu startet
- **THEN** wird der Timer aus dem gespeicherten Zielzeitpunkt mit korrekter Restzeit oder als abgelaufen wiederhergestellt und es entsteht keine doppelte Benachrichtigung

### Requirement: Kompakte Timerleiste beim Eintragen

Während eines aktiven Trainings SHALL eine kompakte Leiste mit Trainingszeit und gegebenenfalls Pausen-Restzeit sichtbar bleiben, auch über der Zahlentastatur. Öffnen und Schließen der großen Timeransicht MUST Eingabefokus und eingegebene Werte erhalten.

#### Scenario: Timer während der Eingabe
- **GIVEN** ein fokussiertes Gewichtsfeld mit sichtbarer Zahlentastatur und laufendem Timer
- **WHEN** der Nutzer einen Wert tippt
- **THEN** bleibt die Restzeit sichtbar und der Wert wird gespeichert

### Requirement: Live Activity für Training und Pause

Auf unterstützten iPhones SHALL während eines aktiven Trainings eine Live Activity laufen: ohne Pause mit Trainingszeit seit Start, mit laufender Pause zusätzlich mit Restzeit, nach Ablauf mit 0:00. Workout-Ende, Löschen, Abmelden und Kontowechsel MUST sie beenden.

#### Scenario: Training ohne Pause gesperrt
- **GIVEN** ein aktives Training ohne laufenden Timer
- **WHEN** das iPhone gesperrt wird
- **THEN** zeigt die Live Activity die Trainingszeit seit Start und keinen Pausen-Countdown

#### Scenario: Training beenden
- **GIVEN** eine laufende Live Activity
- **WHEN** der Nutzer das Training beendet
- **THEN** wird die Live Activity beendet und keine Pause mehr angezeigt

#### Scenario: Live Activities deaktiviert
- **GIVEN** der Nutzer hat Live Activities in iOS deaktiviert
- **WHEN** eine Pause gestartet wird
- **THEN** funktionieren In-App-Timer und Benachrichtigung unverändert

### Requirement: Datenschutz der Live Activity

Die Detailanzeige ist standardmäßig aktiv und SHALL Trainingstitel, aktuelle Übung und Satzposition (z. B. „Satz 2 von 4“) zeigen – auch nach erfasstem Satz und während einer Pause (dann der als Nächstes anstehende Satz). Der Nutzer kann sie abschalten; dann DÜRFEN Systemflächen nur Trainings-/Pausenstatus und Zeiten zeigen. Gewichte und Wiederholungen MUST NOT erscheinen.

#### Scenario: Übung nach erfasstem Satz
- **GIVEN** Standardeinstellung, Training „Pull“, Latzug mit drei Sätzen, der erste ist erfasst
- **WHEN** das iPhone gesperrt wird, mit oder ohne laufende Pause
- **THEN** zeigt die Live Activity „Latzug“ und „Satz 2 von 3“ und die Zeit, aber kein Gewicht

#### Scenario: Details abgeschaltet
- **GIVEN** der Nutzer hat „Details auf Sperrbildschirm“ abgeschaltet
- **WHEN** das iPhone gesperrt wird
- **THEN** zeigt die Live Activity nur „Training“ bzw. „Pause“ und die Zeiten, ohne Übungsnamen

#### Scenario: Detailfreigabe aktiv
- **GIVEN** die Detailanzeige ist aktiv und der Nutzer trainiert Latzug im Training „Pull“ im ersten von drei Sätzen
- **WHEN** das iPhone gesperrt wird
- **THEN** zeigt die Live Activity „Pull“, „Latzug“, „Satz 1 von 3“ und die Zeit, aber kein Gewicht

#### Scenario: Antippen der Live Activity
- **GIVEN** eine Live Activity eines anderen, inzwischen abgemeldeten Kontos
- **WHEN** der Nutzer sie antippt
- **THEN** öffnet die App den aktuellen Zugangspfad, zeigt keine Daten des alten Kontos und führt keine Mutation aus
