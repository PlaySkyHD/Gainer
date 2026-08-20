# iPhone-Abnahme: Gerichte und manuelle Ernährungsziele

Diese Checkliste ist der manuelle Restnachweis für OpenSpec-Tasks 10.4 und 13.3. Sie muss auf einem physischen iPhone mit einem eingeladenen Testkonto ausgeführt werden. Ein Start aus Safari ist zulässig; die Installation als PWA ist keine Voraussetzung. Beide Startarten sollten dokumentiert werden.

## Testprotokoll

- iPhone-Modell:
- iOS-Version:
- Startart: Safari / installierte PWA
- Datum und Tester:
- Ergebnis je Szenario: bestanden / fehlgeschlagen, mit Screenshot oder kurzer Fehlerbeschreibung

## 1. Offline-Gericht und Deep Copy

1. Online anmelden, die eigenständige Ansicht „Gerichte“ öffnen und dort mindestens zwei Lebensmittel sowie ein wiederverwendbares Gericht anlegen.
2. Das Gericht duplizieren, das Duplikat vor dem Speichern umbenennen und das Original archivieren; optional archivierte Gerichte einblenden.
3. Flugmodus aktivieren und prüfen, dass die App „Offline“ anzeigt.
4. Im Ernährungstag das aktive Gericht auswählen, einen Portionsfaktor ungleich 1 wählen und die Vorschau kontrollieren.
5. Die Komponenten zu einer Mahlzeit hinzufügen und einen kopierten Eintrag verändern.
6. App schließen beziehungsweise in den Hintergrund legen und anschließend neu öffnen.
7. Erwartung: Bibliothek, Archivstatus, kopierte Einträge und Änderung sind weiterhin vorhanden; die Vorlage blieb unverändert und der Sync ist ausstehend.

## 2. Benannte Zielphasen offline

1. Weiterhin offline eine benannte Cut-, Erhalt-, Aufbau- oder benutzerdefinierte Phase mit Start- und optionalem inklusivem Enddatum anlegen.
2. Eine Phase im Grammmodus und eine Folgephase im Prozentmodus erfassen; die Prozentwerte müssen exakt 100 Prozent ergeben.
3. Beim Planen hinter einer offenen Phase den Hinweis zum Beenden am Vortag prüfen und ausdrücklich bestätigen.
4. Bei mehr als 10 Prozent 4/4/9-Abweichung im Grammmodus den separaten Warnschritt prüfen.
5. Zwischen letztem Tag der alten und erstem Tag der neuen Phase wechseln und Name, Kategorie, Zeitraum sowie die jeweils richtigen kanonischen Grammziele kontrollieren.
6. App neu öffnen.
7. Erwartung: Beide datumsabhängigen Ansichten und der ausstehende lokale Stand bleiben erhalten; es erscheinen keine automatisch vorgeschlagenen Werte.

## 3. Wiederverbindung und idempotenter Sync

1. Flugmodus deaktivieren und die App im Vordergrund öffnen. Auf iOS wird kein garantierter Hintergrund-Sync erwartet.
2. Synchronisierung starten beziehungsweise den automatischen Vordergrund-Sync abwarten.
3. Verbindung unmittelbar nach dem Senden kurz unterbrechen und danach erneut synchronisieren.
4. Erwartung: Gericht, Zielversion und Ernährungstag erscheinen serverseitig genau einmal; ein Retry erzeugt keine Duplikate.

## 4. Sichtbarer Konflikt

1. Auf dem iPhone offline eine vorhandene Gerichtsvorlage ändern.
2. Dieselbe Vorlage mit dem aktiv schreibenden Testgerät online ändern und synchronisieren.
3. Das iPhone wieder verbinden und synchronisieren.
4. Erwartung: Die App zeigt einen Konflikt und verwirft beziehungsweise überschreibt keine Seite still; bereits kopierte Ernährungseinträge bleiben unverändert.

## 5. Abgelaufene Sitzung und Kontotrennung

1. Auf dem iPhone offline eine Zielversion oder Gerichtänderung erzeugen.
2. Die Sitzung serverseitig ablaufen lassen oder das Konto deaktivieren, bevor das Gerät synchronisiert.
3. Wieder online gehen und synchronisieren.
4. Erwartung: Die Änderung bleibt lokal ausstehend und wird nicht ohne erneute Anmeldung hochgeladen.
5. Falls ein zweites Testkonto verwendet wird, damit anmelden.
6. Erwartung: Daten und Outbox des ersten Kontos sind für das zweite Konto nicht sichtbar und werden nicht unter dessen Identität synchronisiert.

Tasks 10.4 und 13.3 dürfen erst abgehakt werden, wenn alle fünf Szenarien auf echter Hardware dokumentiert bestanden sind.
