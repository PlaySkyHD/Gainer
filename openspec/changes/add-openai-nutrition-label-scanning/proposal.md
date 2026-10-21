# Proposal

## Why

Der Etiketten-Scan in der App ruft `POST /api/v1/nutrition/label-scans` auf, doch dafür gibt es im Backend keinen Endpunkt mehr. Geplant war Azure Document Intelligence. Die Azure-Ressourcen gibt es nicht mehr, der Scan schlägt deshalb immer fehl. Der OpenAI-Zugang für die Mahlzeiten-Schätzung funktioniert dagegen.

## What Changes

- Neuer Endpunkt `POST /api/v1/nutrition/label-scans` (multipart, genau ein Bild). Er liest die Nährwerttabelle mit dem OpenAI-Bildmodell und dem bestehenden `OpenAiResponsesProvider`.
- Das Modell gibt nur ab, was gedruckt ist: Bezug (pro 100 g, pro 100 ml, pro Portion), Portionsgewicht sowie kcal, kJ, Eiweiß, Kohlenhydrate und Fett mit Textbeleg. Es rechnet nichts selbst.
- Die Umrechnung auf 100 g erfolgt fest im Server: Portion über das Portionsgewicht, 100 ml als 100 g, kJ in kcal. Unplausible Werte werden markiert und können nicht übernommen werden.
- Die App zeigt den Bezug auf Deutsch, formatiert die Zahlen deutsch und meldet „keine Nährwerttabelle erkannt“ verständlich.
- Die leere Change `add-azure-nutrition-label-scanning` entfällt.

### Non-Goals

- Keine Texterkennung auf dem Gerät.
- Kein Ersatz für das Azure-Backup. Das ist ein eigenes Thema in Issue #66.

## Capabilities

- **Neu:** `nutrition-label-scanning`.

## Impact

- Backend: `NutritionLabelScanDraft` (Core), `OpenAiNutritionLabelScanner`, `NutritionController.ScanLabel`, Verträge und OpenAPI. Der Scan nutzt dasselbe Tageslimit und dieselbe Bildbereinigung wie die Mahlzeiten-Schätzung.
- Flutter: Anzeige im Sheet „Vorschlag prüfen“ und Fehlertext `no_nutrition_label`. Die API-Form bleibt unverändert.
- Betrieb: keine neue Konfiguration und kein neues Secret.
