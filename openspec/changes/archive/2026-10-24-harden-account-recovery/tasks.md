# Tasks

## 1. Server

- [x] 1.1 `creation-options` mit frischer Anmeldung oder Passwort, sonst 403 `reauthentication_required` (D1).
- [x] 1.2 `POST /api/v1/auth/logout-all` (D2).
- [x] 1.3 Platzhalter-Hash für unbekannte und blockierte Konten.

## 2. App

- [x] 2.1 Passwortabfrage beim Anlegen eines Passkeys; falsches Passwort und Abbruch.
- [x] 2.2 „Auf allen Geräten abmelden“ mit Bestätigung, Fehlerdialog und Offline-Hinweis.
- [x] 2.3 Unschärfe im App-Switcher (D3).
- [x] 2.4 `debugPrint` nur im Debug-Build.

## 3. Prüfung

- [x] 3.1 Integrationstests für Passwortbestätigung und Überall-abmelden, Widget- und Controller-Tests in der App, Goldens „Mehr“.
- [x] 3.2 Auf dem iPhone: Passkey nach mehr als 5 Minuten anlegen (Passwortabfrage), App-Switcher zeigt Unschärfe, Face ID und Passkey-Sheet bleiben scharf, „Auf allen Geräten abmelden“.
