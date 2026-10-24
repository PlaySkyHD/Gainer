# Design

## D1 Frische Anmeldung

Ein Passkey überlebt jede Geräte-Session. Deshalb reicht ein Access-Token allein nicht, um einen anzulegen. Als „frisch“ gilt die Anmeldung der aktuellen Geräte-Session (`CreatedAt`, also Passwort- oder Passkey-Login) innerhalb der letzten 5 Minuten. Der häufige Fall „anmelden, dann Passkey anlegen“ braucht so kein zweites Passwort. Später prüft `CheckPasswordSignInAsync` das mitgesendete Passwort; Fehlversuche zählen für die Sperre. Nur `creation-options` prüft: Der Zustand für die Registrierung ist an das Konto gebunden und gilt 5 Minuten.

Löschen braucht keine Bestätigung: Ein Angreifer könnte damit nur einen Passkey entfernen, das Passwort bleibt gültig.

## D2 Überall abmelden

`logout-all` nutzt `RevokeAllAsync`, wie die Deaktivierung. Die App ruft den Server zuerst auf und meldet sich erst nach Erfolg lokal ab. Sonst sähe der Nutzer „abgemeldet“, obwohl andere Geräte noch angemeldet sind. Passkeys bleiben erhalten; der Dialog verweist auf „Passkeys“, um unbekannte zu entfernen.

## D3 App-Switcher

iOS macht den Schnappschuss nach `sceneDidEnterBackground`. Die Unschärfe kommt dort hinzu und geht in `sceneWillEnterForeground` wieder weg. `sceneWillResignActive` wäre zu früh: Face ID, das Passkey-Sheet und Systemdialoge würden die App dann unscharf machen.
