# Design

## D1 Prompt und Schema

Das Schema verlangt `saltGrams` (Zahl oder `null`, 0–100) für jeden Bestandteil. `kilocalories` darf 0 sein, damit ein Bestandteil „Salz“ möglich ist. Die Regeln stehen im Prompt:
1. Salz nur, wenn es im gekauften oder servierten Essen steckt.
2. `null` für schlichte oder selbstgekochte Zutaten; Kochsalz nie raten.
3. Nur bei genannter Menge einen Bestandteil „Salz“ mit 0 kcal, 0 g Makros und `saltGrams` gleich der Menge anlegen (Prise 0,5 g, Teelöffel 6 g).

Das Schema heißt jetzt `meal-estimate-v2`.

## D2 Vorschlag in der App

- **Zeile:** „350 g · 890 kcal · ~3,5 g Salz · mittel“. Beim Bestandteil „Salz“ entfällt die Angabe „~“.
- **Hinweis:** „Selbst gesalzen? Salz hinzufügen“ erscheint, solange kein Bestandteil „Salz“ vorliegt, und wechselt im Sheet zur Salz-Schnellwahl.
- **Teilübernahme:** `confirmEstimatedComponent` entfernt nur den übernommenen Bestandteil. Ist keiner mehr übrig, wird der Vorschlag `null`. 0 kcal sind beim Übernehmen erlaubt.
