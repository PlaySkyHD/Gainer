# Proposal

## Why

Ein Repo-weites Review (Issue #175) hat neun Stellen gefunden, an denen Specs dem Code widersprechen oder veraltet sind. In allen Fällen ist der Code richtig. Die Specs hatten zum Beispiel noch Protokoll 3, schrieben 0 kcal aus, wenn der Code 0 kcal erlaubt, und ließen die HealthKit-Übernahme der Schritte nicht zu.

## What Changes

Nur Specs ändern sich, kein Code. Jede Stelle wurde im Code geprüft, bevor sie angepasst wurde.

- **offline-sync:** „Protokoll v3“ wird zu „die aktuelle Protokollversion“.
- **meal-tracking:** Kilokalorien dürfen 0 sein, weil „Selbst gesalzen“ 0 kcal hat.
- **body-tracking:** Die Ausnahme für die automatische Übernahme der Schritte aus Apple Health steht in der Anforderung zu HealthKit. Die Übersicht übernimmt sie beim Laden.
- **ios-app:** Node.js und npm sind nur im Workflow „OpenSpec“ für die gepinnte CLI erlaubt.
- **training-session:** Der Button heißt „Ja, Vorwerte verwenden“. Die Vorwertquellen werden mit ihren Bezeichnungen im Sheet beschrieben, „Trainingsplan“ erscheint nur bei einem Training aus einem Plan.
- **strava-export:** Strava sendet höchstens sechs Versuche, das sind fünf Wiederholungen. Der Code bricht nach dem sechsten Versuch ab.
- **account-access:** Die Szenarien ohne GIVEN bekommen einen Ausgangszustand.
- **reusable-meals und training-statistics:** Englische Begriffe werden übersetzt, zum Beispiel „Nutrition Day“, „Nutrition-Entry-Snapshot“, „Best Set“ und „Estimated 1RM“.
- **body-tracking:** „Writer“ wird zu „Schreibgerät“.

Überschriften der Anforderungen bleiben unverändert, damit die MODIFIED-Deltas zuzuordnen sind. Die Überschrift „Gericht als atomare Deep Copy hinzufügen“ ist deshalb noch englisch.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `offline-sync`, `meal-tracking`, `body-tracking`, `ios-app`, `training-session`, `strava-export`, `account-access`, `reusable-meals`, `training-statistics`: Textkorrekturen, keine Verhaltensänderung im Code.

## Impact

- Nur `openspec/specs/` nach dem Archivieren, kein Code, keine API-Änderung.
- Der Workflow „OpenSpec“ bleibt grün, sobald der Change archiviert ist.
