# Design

## D1 Opake Access-Tokens statt JWT

Access-Tokens erzeugt der eingebaute Bearer-Token-Handler von ASP.NET Core (`AddBearerToken`). Sie sind mit Data Protection verschlüsselt, der Schlüsselring liegt wie bisher dauerhaft im Volume. Ein JWT bringt nichts, weil nur die eigene API die Tokens liest. Die Tokens enthalten Nutzer-ID, Rollen und die ID der Geräte-Session (`gainer:device_session`). `AccessTokenIssuer` baut sie aus `SignInManager.CreateUserPrincipalAsync`.

## D2 Refresh-Tokens selbst verwaltet

Das Refresh von `MapIdentityApi` hat weder Rotation noch Wiederverwendungserkennung noch Widerruf pro Gerät. Deshalb verwaltet `DeviceSessionService` die Refresh-Tokens selbst: 32 Zufallsbytes, Base64Url, in der Datenbank nur als SHA-256-Hash (wie bei Einladungen). Pro Session werden der aktuelle und der vorherige Hash gespeichert, beide eindeutig indiziert.

## D3 Rotation, Kulanzzeit und Wiederverwendung

- Aktueller Token: neuer Token wird aktuell, der alte wird „vorheriger“, `RotatedAt` = jetzt.
- Vorheriger Token innerhalb von `ReuseGracePeriod` (1 Minute) nach der Rotation: Die Antwort ging vermutlich verloren. Es wird einmal erneut ein Token ausgestellt, der vorherige bleibt Bezug, `RotatedAt` bleibt. Der Token aus der verlorenen Antwort wird als „verworfen“ gespeichert; kommt er zurück oder folgt ein zweiter Retry, wird die Session widerrufen (nachgezogen in `harden-auth-edge`, D2).
- Vorheriger Token danach: Eine Kopie ist im Umlauf. Die Session wird widerrufen.
- Gleichzeitige Refreshes derselben Session scheitern bis auf einen an der Versionsprüfung. Die App verhindert das, weil sie Refreshes bündelt (D6).

## D4 Prüfung pro Request

`DeviceSessionValidationMiddleware` läuft nach `UseAuthentication`. Für Bearer-authentifizierte Requests prüft sie mit einer Abfrage über Primärschlüssel, dass die Session existiert, nicht widerrufen und nicht abgelaufen ist und das Konto aktiv ist. So wirken Logout und Deaktivierung sofort und nicht erst nach Ablauf des Access-Tokens. Andere Authentifizierungsschemata (Testschemata) bleiben unberührt.

## D5 Laufzeit

`Security:DeviceSessions:IdleLifetime` (Standard 60 Tage) gleitet bei jedem Refresh. `AbsoluteLifetime` ist ungesetzt; gesetzt begrenzt es die Session ab Anmeldung. Beim Login werden abgelaufene und widerrufene Sessions des Kontos gelöscht.

## D6 App

- `ApiClient` erneuert den Access-Token 30 Sekunden vor Ablauf und nach einem 401 einmal. Multipart-Uploads werden nicht wiederholt, weil ihr Body nicht erneut lesbar ist. Parallele Requests teilen sich einen laufenden Refresh.
- Nach jeder Rotation ruft `ApiClient` `onRefreshTokenRotated` auf, und `ApiSessionService` schreibt den Checkpoint neu. Stürzt die App zwischen Rotation und Speichern ab, deckt die Kulanzzeit aus D3 den nächsten Start ab, sofern er innerhalb einer Minute erfolgt. Sonst ist eine neue Anmeldung nötig.
- Ein 401 auf den Refresh ruft `onSessionRejected` auf. `MobileAuthController` schließt den Kontobereich, löscht den Checkpoint und zeigt die Anmeldung mit Hinweis. Die lokale Datenbank des Kontos und wartende Änderungen bleiben erhalten.
- Ohne Netz öffnet die App wie bisher das bekannte Konto offline. Der Refresh folgt, sobald wieder Requests möglich sind.
- Die Kontoprüfung vor Sync-Schreibzugriffen übernimmt allein der Server über `X-Gainer-Account-Id`. Die frühere clientseitige Prüfung über das Antiforgery-Token entfällt.
