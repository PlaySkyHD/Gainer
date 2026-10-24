# Proposal

## Why

Rückmeldung vom Gerät zur neuen BLS-Suche:
- Nach dem Übernehmen eines Treffers bleibt das Sheet offen. Beim nächsten Öffnen stehen noch die alte Suche und alte Treffer da.
- Die Mahlzeit-Tabs stehen auch auf den Unterseiten, obwohl die Mahlzeit schon vorher gewählt ist.
- BLS und Open Food Facts stehen in zwei Gruppen. Die Produktsuche startet nur über die Tastatur („Suchen“), das ist schwer zu entdecken.

## What Changes

- **Übernehmen schließt das Sheet.** Gemeint ist ein Treffer aus Zuletzt, Suche oder Barcode, ein manueller Eintrag oder Salz. Das Sheet schließt nur, wenn das Speichern gelingt. Gerichte und die KI-Schätzung (mehrere Bestandteile) bleiben wie bisher.
- **Jedes Öffnen beginnt leer:** Startseite, leere Suche, keine alten Treffer, Menge 100 g, Quelle „Alle“.
- **Mahlzeit-Tabs** stehen nur auf der Startseite „Hinzufügen“.
- **Eine Trefferliste** für BLS und Open Food Facts. Jede Zeile nennt ihre Quelle („BLS 4.0“ oder „Open Food Facts“).
- **Quellenfilter** „Alle · BLS · Produkte“ über der Liste, sobald gesucht wird.
- **Produktsuche sichtbar:** Über der Liste steht die Schaltfläche „In Open Food Facts suchen“, solange für die aktuelle Eingabe noch nicht online gesucht wurde. Absenden über die Tastatur und der Filter „Produkte“ starten die Suche ebenfalls.

- **Mehrere hinzufügen:** Langes Drücken auf „Hinzufügen“ einer Mahlzeit oder auf das Plus bietet „Mehrere hinzufügen“ an. In diesem Modus bleibt das Sheet nach jedem Eintrag offen, leert Suche und Menge für das nächste Lebensmittel und zeigt „„Name“ hinzugefügt.“. Ein Haken oben rechts schließt es.
- **Startseite gegliedert** in „Finden“ (Suchen, Zuletzt, Barcode), „Mit KI“ (Schätzen, Etikett) und „Selbst eintragen“ (Gerichte, Manuell, Salz). Jede Unterseite beginnt oben, auch wenn die Startseite gescrollt war.

### Non-Goals

- Keine automatische Online-Suche beim Tippen. Open Food Facts begrenzt Suchanfragen, und der Server teilt sein Budget.
- Keine gemeinsame Rangfolge über beide Quellen: In „Alle“ stehen BLS-Treffer vor Produkten.

## Capabilities

- **Neu:** `food-search-sheet`.

## Impact

- **App:** `nutrition_screen_cupertino.dart`, `nutrition_view_model.dart`; Widget-Tests und Goldens.
- **Backend, API, Sync:** keine Änderung.
- **Security:** keine Auswirkung.
- **Breaking Changes:** keine.
