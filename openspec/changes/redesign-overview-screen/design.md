# Design

## D1 Farben

Kategoriale Farben für die drei Makros, mit dem Paletten-Validator (dataviz) für alle Paare geprüft. In beiden Modi bestehen Helligkeitsband, Chroma, Farbfehlsichtigkeit (ΔE ≥ 13), Normalsicht (ΔE ≥ 26) und Kontrast ≥ 3:1 zur Fläche.

| Rolle | Hell (Fläche #FFFFFF) | Dunkel (Fläche #1C1C1E) |
| --- | --- | --- |
| `carbohydrate` | `#008300` | `#008300` |
| `protein` | `#2A78D6` | `#3987E5` |
| `fat` | `#D55181` | `#D55181` |

- Werte und Beschriftungen bleiben in Textfarben; die Farbe trägt nur ein Punkt vor dem Namen und der Balken. Die Bedeutung hängt damit nie allein an der Farbe.
- Über dem Ziel färbt sich der Balken wie bisher in `warning`. Ballaststoffe (Mindestziel) und Salz bleiben neutral bzw. in der Akzentfarbe.
- Der kcal-Ring bleibt in `accent`.

## D2 Aufbau der Übersicht

`GainerScaffold(title: 'Übersicht')`:
- `leading`: `GainerDayNavigator` mit „Heute“, „Gestern“, „Morgen“ oder „Sa. 18. Okt.“. Die Pfeile rufen `select(selected ± 1 Tag)`. Ein Tipp auf den Text scrollt zum Kalender (`Scrollable.ensureVisible`).
- `trailing`: nur „…“ für den Rhythmus.
- „Zu heute“ steht als Textknopf rechts neben der Datumsüberschrift der Tagesansicht, nur wenn ein anderer Tag gewählt ist. In der Kopfzeile läge es bei langen Daten über dem rechten Pfeil der Tages-Pille.
- `children`: Fehlerhinweis, `CalendarDayView`, danach `CalendarMonthGrid` in einer eigenen Gruppe.
- Ein Tipp auf einen Tag im Raster wählt ihn und scrollt zum Anfang der Tagesansicht.

`CalendarDayView` reiht die Karten neu: Plan bzw. Heute-Karte, Training, Ernährung, Gewicht, Trainingsübersicht, Check-in.

## D3 Ernährungskarte

- In `_Macro` (Kalender) und in der Tageskarte (Essen): Punkt in der Makrofarbe vor dem Namen, Balken in derselben Farbe.
- Die Zeile mit Ballaststoffen und Salz steht mittig: zwei Spalten mit der Breite einer Makrospalte.
- Bei Textgröße 2 werden die Makros wie bisher untereinander gestapelt.
