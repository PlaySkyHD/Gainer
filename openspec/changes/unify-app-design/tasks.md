# Tasks

## 1. Gemeinsame Bausteine

- [ ] 1.1 `showGainerSheet` mit Griff, Wischen-zum-Schließen und Zurückfedern in `ui/core/components/gainer_sheet.dart`; Pausentimer-Sheet darauf umstellen; Widget- und Golden-Tests.
- [ ] 1.2 `GainerSwipeToDelete` (Wischen nach links, Bestätigungsdialog, rote Fläche) aus dem Tagebuch extrahieren; Tagebuch nutzt ihn; Widget-Test.
- [ ] 1.3 `GainerSectionHeader` (Titel links, Zusatz rechts) und `GainerDateRow` (Wert rechts, Datumsauswahl im Sheet); Widget- und Golden-Tests.

## 2. Heute

- [ ] 2.1 `progress_screen` und `exercise_progress_section` nach D1 umstellen; Fachtests grün, Goldens Hell/Dunkel neu.

## 3. Check-in und Apple Health

- [x] 3.1 `body_screen` nach D1/D2 umstellen (Toolbar „+“, Zielkarte antippbar, Verlauf als Gruppe); Fachtests grün, Goldens neu.
- [x] 3.2 `health_review_screen_cupertino` mit `GainerDateRow`, gruppierten Abschnitten und Fußnoten; Fachtests grün, Goldens neu.

## 4. Essen

- [ ] 4.1 Toolbar mit Datum, Kalender und „+“; Tagesübersicht und Ziele als gruppierte Karten.
- [ ] 4.2 Mahlzeit-Einträge mit Antippen, Wischen-zum-Löschen, Kontext-Sheet und Neuordnen-Sheet statt Inline-Buttons; Fachtests auf Gesten umgestellt, Goldens neu.
- [ ] 4.3 Sheets und Dialoge des Ernährungsbereichs auf `showGainerSheet` und `showGainerStackedDialog`.

## 5. Mehr, Sync, Coach, Zugang

- [ ] 5.1 Mehr-Menü, Sync & Gerät und Coach nach D1 (Listenzeilen, Fußnoten, eine Abschluss-Pille); Fachtests grün, Goldens neu.
- [ ] 5.2 Anmeldung und Kontoverwaltung nach D1; Fachtests grün, Goldens neu.

## 6. Abschluss

- [ ] 6.1 Gesamtdurchsicht aller Tabs in Hell und Dunkel; TestFlight-Build.
- [ ] 6.2 Abnahme auf dem iPhone durch den Nutzer.
