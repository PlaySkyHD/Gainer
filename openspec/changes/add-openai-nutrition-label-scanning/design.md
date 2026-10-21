# Design

## D1 Modell liest, Server rechnet

Das Modell bekommt das bereinigte JPEG mit `detail: high`, weil Nährwerttabellen klein gedruckt sind. Es antwortet über ein striktes JSON-Schema und hat keine Tools. Die Werte gibt es so ab, wie sie in genau einer Spalte gedruckt sind. Bevorzugt wird pro 100 g, dann pro 100 ml, dann pro Portion. Zu jedem Wert liefert es einen kurzen Textbeleg (höchstens 120 Zeichen).

`NutritionLabelScanDraft.Create` rechnet daraus deterministisch:

| Bezug | Faktor auf 100 g | Status |
| --- | --- | --- |
| pro 100 g | 1 | `Confirmed` |
| pro 100 ml | 1 (1 ml ≈ 1 g) | `Converted` |
| pro Portion mit Gewicht | 100 / Portionsgewicht | `Converted` |
| pro Portion ohne Gewicht | – | `Missing`, Originalwert bleibt |

Fehlt kcal, aber kJ ist gedruckt, wird kcal als kJ / 4,184 berechnet (Status `Converted`, Beleg aus kJ). Gerundet wird kcal auf ganze Zahlen und Makros auf eine Nachkommastelle.

## D2 Plausibilität

- kcal pro 100 g muss größer als 0 und höchstens 950 sein.
- Jedes Makro pro 100 g darf höchstens 100 g betragen.
- Negative Werte gelten als `Implausible`.
- `canConfirm` ist nur wahr, wenn kcal pro 100 g vorliegt und die Makrosumme höchstens 105 g beträgt. Die 5 g Spielraum decken Rundungen auf Etiketten ab.

## D3 Fehler

| Fall | Code | HTTP |
| --- | --- | --- |
| Kein Bild | `invalid_input` | 400 |
| Mehr als ein Bild | `too_many_images` | 400 |
| Keine Nährwerttabelle erkannt | `no_nutrition_label` | 422 |
| Ungültige Modellantwort | `invalid_provider_response` | 502 |
| Anbieter ausgelastet, Zeitüberschreitung oder nicht erreichbar | `provider_rate_limited`, `provider_timeout`, `provider_unavailable` | 429, 504, 503 |
| Tageslimit erreicht | `daily_budget_exhausted` | 429 |

## D4 Kontingent und Datenschutz

Der Scan zählt zum Tageslimit `MealEstimation`, weil beides KI-Anfragen im Ernährungsbereich sind. Das Bild durchläuft `MealImageSanitizer` (EXIF entfernen, neu kodieren) und wird danach im Speicher geleert. Die Anfrage läuft mit `store: false`. Die Einwilligung zum Hochladen holt die App vor der Aufnahme ein.
