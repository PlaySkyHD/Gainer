# overview-screen

## ADDED Requirements

### Requirement: Übersicht mit dem Tag zuerst

Der erste Tab SHALL „Übersicht“ heißen. Die Seite SHALL zuerst die Werte des gewählten Tages zeigen, in der Reihenfolge Plan oder Training, Ernährung, Gewicht, Trainingsübersicht, Check-in. Der Monatskalender SHALL als letzte Karte darunter stehen.

#### Scenario: App öffnen
- **GIVEN** heute ist Samstag, der 24. Oktober
- **WHEN** der Nutzer die App öffnet
- **THEN** zeigt der Tab „Übersicht“ oben „Heute“ und die Ernährung von heute vor dem Monatskalender

#### Scenario: Tag im Kalender wählen
- **GIVEN** der Nutzer hat bis zum Monatskalender gescrollt
- **WHEN** er den 18. Oktober antippt
- **THEN** scrollt die Seite nach oben und zeigt die Werte des 18. Oktober

### Requirement: Tageswechsel oben

Oben links SHALL die Tages-Pille stehen. Die Pfeile SHALL einen Tag zurück oder vor wechseln, auch über Monatsgrenzen. Ein Tipp auf den Text SHALL zum Monatskalender scrollen. Ist ein anderer Tag als heute gewählt, SHALL „Zu heute“ neben der Datumsüberschrift zurück zum heutigen Tag führen.

#### Scenario: Ein Tag zurück
- **GIVEN** die Übersicht zeigt den 1. November
- **WHEN** der Nutzer den linken Pfeil antippt
- **THEN** zeigt sie den 31. Oktober, und der Kalender unten zeigt Oktober

#### Scenario: Zurück zu heute
- **GIVEN** die Übersicht zeigt den 18. Oktober
- **WHEN** der Nutzer „Zu heute“ antippt
- **THEN** zeigt sie den heutigen Tag, und der Button verschwindet

### Requirement: Farbige Makros

Kohlenhydrate, Eiweiß und Fett SHALL auf der Ernährungskarte der Übersicht und auf der Tageskarte im Tab „Essen“ je eine eigene Farbe für Punkt und Balken haben. Werte und Namen MUST in Textfarben stehen. Über dem Ziel SHALL der Balken die Warnfarbe zeigen. Ballaststoffe und Salz SHALL in einer eigenen, zentrierten Zeile stehen.

#### Scenario: Makros unterscheiden
- **GIVEN** ein Tag mit 51 g Kohlenhydraten, 66 g Eiweiß und 29 g Fett
- **WHEN** der Nutzer die Ernährungskarte ansieht
- **THEN** hat jede Makrospalte einen farbigen Punkt und Balken in ihrer Farbe, und die Werte stehen in Textfarbe

#### Scenario: Über dem Ziel
- **GIVEN** Fett 95 g bei einem Ziel von 80 g
- **WHEN** die Karte angezeigt wird
- **THEN** ist der Fett-Balken voll und in Warnfarbe
