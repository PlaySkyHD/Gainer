# Design

## D1 Gramm bleiben maßgeblich

`NutritionPortion(PieceGrams, PieceCount?)`:
- Stückgewicht liegt über 0 und höchstens bei 5.000 g, die Stückzahl über 0 und höchstens bei 1.000.
- Mit Stückzahl gilt `|round(Stückzahl × Stückgewicht, 2) − AmountGrams| ≤ 0,01`.
- Ein Stückgewicht ohne Stückzahl ist erlaubt: Es merkt sich das Gewicht, auch wenn in Gramm eingegeben wurde.
- Eine Stückzahl ohne Stückgewicht ist ungültig.
- Datenbank-Constraints sichern dasselbe ab.

## D2 Quellen

- **Open Food Facts:** `serving_quantity` nur mit der Einheit g, ml oder ohne Einheit, sonst leer.
- **KI-Schätzung:** Das Modell setzt `pieceCount` und `pieceGrams` nur bei gezählten Dingen und rechnet `amountGrams` = Stückzahl × Stückgewicht. Passt das nicht, verwirft der Server die Stückangabe und behält die Schätzung in Gramm.
- **Gerichte:** Beim Übernehmen mit Portionsfaktor wird die Stückzahl skaliert und die Grammzahl daraus neu berechnet.

## D3 Oberfläche

- **Hinzufügen:** Ist „Anzahl“ gesetzt, gilt Anzahl × Stückgewicht des gewählten Lebensmittels. Die Grammzahl im Feld „Menge“ wird dann ignoriert. Wer in „Menge“ tippt, leert die Anzahl.
- **Formular:** Ändert sich „Gewicht pro Stück“ oder „Anzahl“, wird „Menge“ neu gesetzt.
- **Minus und Plus** schalten in ganzen Stücken. Unter 1 geht es auf ½, darunter wird die Anzahl leer. Bei großer Schrift steht die Beschriftung über den Knöpfen.
