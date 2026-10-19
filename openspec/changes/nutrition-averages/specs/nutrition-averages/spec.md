# nutrition-averages

## ADDED Requirements

### Requirement: Durchschnitt aus lokalen Tagen

Die App SHALL für die letzten 7 und 30 Kalendertage Ø Kalorien, Protein, Kohlenhydrate und Fett je erfasstem Tag aus den lokalen Ernährungstagen berechnen, ohne Netzwerk. Tage ohne Einträge MUST NOT als 0 kcal zählen. Heute MUST nur zählen, wenn es Einträge hat; sonst endet das Fenster gestern.

#### Scenario: Arbeitsbeispiel 7 Tage
- **GIVEN** heute ist der 19.10.2026 mit 1.900 kcal (Protein 130 g, Kohlenhydrate 200 g, Fett 60 g); erfasst sind außerdem 13.10. mit 2.000 kcal (120/250/70), 14.10. mit 2.300 (150/260/80), 15.10. mit 2.530 (160/300/90) und 17.10. mit 2.070 (140/230/70); 16.10. und 18.10. sind leer
- **WHEN** der Nutzer „7 Tage“ wählt
- **THEN** zeigt die App „Ø 2.160 kcal“ (10.800 / 5), „5 von 7 Tagen erfasst“, Protein 140 g (700 / 5), Kohlenhydrate 248 g (1.240 / 5), Fett 74 g (370 / 5)

#### Scenario: Heute ohne Einträge
- **GIVEN** dieselben Daten, aber heute hat keinen Eintrag
- **WHEN** der Nutzer „7 Tage“ wählt
- **THEN** reicht das Fenster vom 12.10. bis 18.10., „4 von 7 Tagen erfasst“, Ø 2.225 kcal (8.900 / 4)

#### Scenario: 30 Tage
- **GIVEN** zusätzlich der 1.10. mit 3.000 kcal
- **WHEN** der Nutzer „30 Tage“ wählt
- **THEN** zählt der 1.10. mit und es sind „6 von 30 Tagen erfasst“

### Requirement: Zielvergleich

Gilt ein Zielplan, SHALL die App das Kalorienziel des jeweiligen Tages verwenden und die erfassten Tage mit |kcal − Ziel| ≤ 10 % des Ziels als „im Zielbereich“ zählen (Grenze inklusive). Ohne Zielplan MUST der Vergleich ausgeblendet sein.

#### Scenario: Grenzen im Arbeitsbeispiel
- **GIVEN** das Ziel 2.300 kcal und das Arbeitsbeispiel 7 Tage
- **WHEN** die App vergleicht
- **THEN** zeigt sie „Ziel Ø 2.300 kcal“ und „3 von 5 Tagen im Zielbereich ±10 %“ (2.300 exakt, 2.530 = +10 % und 2.070 = −10 % zählen; 2.000 und 1.900 nicht)

#### Scenario: Zielwechsel im Zeitraum
- **GIVEN** Ziel 2.000 kcal bis 15.10. und 2.500 kcal ab 16.10.; erfasst sind 15.10. und 16.10. je mit 2.000 kcal
- **WHEN** die App vergleicht
- **THEN** ist Ø Ziel 2.250 kcal und 1 von 2 Tagen im Zielbereich

### Requirement: Einstieg und Ansicht

Der Tab „Essen“ SHALL unter der Tageskarte eine Zeile „Durchschnitt“ mit Kurzwerten zeigen, die das Sheet „Durchschnitt“ mit Umschalter 7 Tage / 30 Tage öffnet. Ohne Einträge MUST die Zeile „Noch keine Einträge“ zeigen und nichts öffnen. Das Diagramm MUST leere Tage ohne Balken darstellen und beschriften.

#### Scenario: Leerer Zustand
- **GIVEN** keine Einträge in den letzten 30 Tagen
- **WHEN** der Nutzer den Tab „Essen“ öffnet
- **THEN** zeigt die Zeile „Noch keine Einträge“ ohne Pfeil
