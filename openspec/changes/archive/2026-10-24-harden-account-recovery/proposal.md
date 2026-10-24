# Proposal

## Why

Zweiter Teil der Sicherheitsanalyse (nach `harden-auth-edge`):

- Ein Passkey ließ sich allein mit einem Access-Token anlegen. Wer kurz ein entsperrtes Handy oder einen gestohlenen Token hatte, bekam so einen dauerhaften Zugang, der Logout und das Widerrufen von Sitzungen überlebt.
- Es gab keinen Weg, alle Geräte eines Kontos abzumelden.
- Bei unbekannten E-Mail-Adressen antwortete der Login schneller, weil kein Passwort-Hash berechnet wurde. So ließ sich herausfinden, welche Konten existieren.
- Die Vorschau im App-Switcher zeigte Körper- und Trainingsdaten.
- Zwei `debugPrint`-Aufrufe schrieben Fehler auch im Release-Build ins Geräteprotokoll.

## What Changes

- **Passkey anlegen:** `creation-options` verlangt eine Anmeldung, die höchstens 5 Minuten alt ist, sonst das Passwort (`{"password": "…"}`). Fehlt beides, antwortet die API mit 403 `reauthentication_required`. Die App fragt dann das Passwort ab.
- **Überall abmelden:** `POST /api/v1/auth/logout-all` widerruft alle Geräte-Sessions des Kontos. In „Mehr“ gibt es dafür „Auf allen Geräten abmelden“; ohne Verbindung ist die Zeile deaktiviert und der Grund steht darunter.
- **Login-Dauer:** Für unbekannte, gesperrte, inaktive oder unbestätigte Konten berechnet die API einen Platzhalter-Hash.
- **App-Switcher:** Beim Wechsel in den Hintergrund legt die App eine Unschärfe über das Fenster.
- **Protokoll:** `debugPrint` nur noch in Debug-Builds.
