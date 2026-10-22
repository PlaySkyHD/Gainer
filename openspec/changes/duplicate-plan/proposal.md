# Proposal

## Why

Ähnliche Pläne (z. B. „Pull 1“ und „Pull 2“) mussten bisher Übung für Übung neu angelegt werden.

## What Changes

- **Kontext-Sheet per langem Drücken** auf einen Plan in der Planliste: „Training beginnen“, „Duplizieren“ und „Archivieren“.
- **Duplizieren** legt „<Name> Kopie“ am Ende der Liste an und öffnet die Kopie im Planeditor, damit sie gleich umbenannt werden kann. Einträge, Sätze, Notizen, Supersets und Vorwerte-Quelle werden übernommen; Plan, Einträge und Supersets bekommen neue IDs.
- Ein Name, der mit „ Kopie“ länger als 160 Zeichen würde, wird vorne gekürzt.

### Non-Goals

- Keine Platzierung direkt unter dem Original: Das würde eine Umsortierung erfordern, die nur bei synchronisierten Plänen möglich ist.

## Capabilities

- **Neu:** `duplicate-plan`.

## Impact

- Flutter: Planliste, Pläne-ViewModel, `TrainingLogRepository.duplicatePlan`. Die Kopie ist ein normales Anlegen eines Plans; keine Backend- oder Sync-Änderung.
