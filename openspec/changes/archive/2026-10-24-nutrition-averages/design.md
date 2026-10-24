# Design

## Decisions

### D1 – Durchschnitt je erfasstem Tag

Ein Tag ist „erfasst“, wenn er mindestens einen Eintrag hat. Nur erfasste Tage gehen in Ø kcal und Ø Makros ein; leere Tage zählen nicht als 0 kcal (sie sind meist vergessene Tage, kein Fasten). Makros mitteln über erfasste Tage, an denen der Wert vorhanden ist.

### D2 – Heute zählt nur mit Einträgen

Das Fenster (7 oder 30 Kalendertage) endet heute, wenn heute Einträge hat. Sonst endet es gestern. So zieht ein noch leerer Tag den Schnitt nicht herunter und das Fenster zeigt immer genau 7 bzw. 30 volle Kalendertage. Ein begonnener, unvollständiger heutiger Tag zählt mit, sobald er einen Eintrag hat; das ist bewusst einfach und nachvollziehbar.

### D3 – Zielvergleich

Je erfasstem Tag gilt das Kalorienziel der Zielphase, die an diesem Datum galt (Phasenwechsel im Zeitraum werden berücksichtigt). Ø Ziel = Mittel dieser Tageswerte. „Im Zielbereich“: |kcal − Ziel| ≤ 10 % des Tagesziels, Grenzen inklusive. Ohne Zielplan entfällt der Vergleich vollständig.

### D4 – Diagramm

Ein Balken je Kalendertag. Tage ohne Einträge haben keinen Nullbalken, sondern nur einen blassen Strich an der Grundlinie und die Legende „n Tage nichts erfasst“. Das Tagesziel ist je Tag eine gestrichelte Linie.

### D5 – Einstieg

Eine Zeile unter der Tageskarte statt eines Menüpunkts: ein Tipp, kein Menü. Sie lädt lokal und aktualisiert sich, wenn sich der Tagesstand ändert.
