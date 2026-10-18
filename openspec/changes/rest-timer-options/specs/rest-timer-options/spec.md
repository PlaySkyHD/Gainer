# rest-timer-options

## ADDED Requirements

### Requirement: Shortcuts starten den Timer

Ein Tipp auf einen Dauer-Shortcut SHALL den Timer sofort mit dieser Dauer starten. Solange ein Timer läuft oder pausiert ist, MUST die Shortcut-Zeile ausgeblendet sein.

#### Scenario: Shortcut tippen
- **GIVEN** die Timeransicht im Zustand bereit
- **WHEN** der Nutzer auf „2:00“ tippt
- **THEN** läuft der Timer mit 2:00 und die Shortcut-Zeile ist ausgeblendet

#### Scenario: Shortcuts nach dem Schließen
- **GIVEN** ein laufender Timer
- **WHEN** der Nutzer den Timer schließt
- **THEN** ist die Shortcut-Zeile wieder sichtbar

### Requirement: Timermenü

Die Timeransicht SHALL über einen „…“-Button ein Menü mit „Timersound“, „Timer bearbeiten“ und „Timer automatisch starten“ anbieten. Der Zustand von „Timer automatisch starten“ MUST im Menü sichtbar sein.

#### Scenario: Menü öffnen
- **GIVEN** die Timeransicht
- **WHEN** der Nutzer „…“ tippt
- **THEN** erscheinen die drei Einträge und „Timer automatisch starten“ zeigt, ob es an ist

### Requirement: Shortcuts verwalten

„Timer bearbeiten“ SHALL die Shortcuts als Liste zeigen, in der der Nutzer Einträge löschen, per Ziehgriff sortieren und über eine Minuten/Sekunden-Auswahl neue Einträge zwischen 5 Sekunden und 30 Minuten hinzufügen kann.

#### Scenario: Shortcut löschen und sortieren
- **GIVEN** die Shortcuts 1:00, 2:00 und 3:00
- **WHEN** der Nutzer 3:00 löscht und 2:00 vor 1:00 zieht
- **THEN** zeigt die Timeransicht die Shortcuts 2:00 und 1:00 in dieser Reihenfolge

### Requirement: Timerton wählen

Der Nutzer SHALL einen Ablaufton aus einer Liste wählen können; ein Tipp spielt den Ton zur Probe. Der gewählte Ton MUST für die Benachrichtigung „Pause vorbei“ und den Ersatzton in der App gelten.

#### Scenario: Ton wählen
- **GIVEN** die Liste „Timersound“
- **WHEN** der Nutzer „Gong“ antippt
- **THEN** ertönt der Gong, „Gong“ ist abgehakt und die nächste Benachrichtigung „Pause vorbei“ nutzt den Gong

### Requirement: Timer automatisch starten

Ist „Timer automatisch starten“ eingeschaltet, SHALL der Timer mit der zuletzt gewählten Dauer starten, sobald im aktiven Training ein Satz vollständig erfasst wird und kein Timer läuft oder pausiert ist. Die Einstellung MUST standardmäßig aus sein.

#### Scenario: Satz erfasst mit Automatik
- **GIVEN** „Timer automatisch starten“ ist an, die Dauer 2:00 und kein Timer läuft
- **WHEN** der Nutzer Gewicht und Wiederholungen eines Satzes einträgt
- **THEN** läuft der Timer mit 2:00

#### Scenario: Laufender Timer bleibt
- **GIVEN** „Timer automatisch starten“ ist an und ein Timer läuft mit 0:40 Restzeit
- **WHEN** der Nutzer einen weiteren Satz erfasst
- **THEN** läuft der Timer unverändert weiter
