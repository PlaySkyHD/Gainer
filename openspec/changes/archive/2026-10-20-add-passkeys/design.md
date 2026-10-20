# Design

## D1 Handler statt SignInManager

`SignInManager.MakePasskey…`/`PasskeySignInAsync` legen den Ceremony-Zustand in ein Cookie. Cookies gibt es seit `mobile-token-auth` nicht mehr. Deshalb ruft `PasskeysController` direkt `IPasskeyHandler<AppUser>` auf, der den Zustand als String zurückgibt, und `PasskeyCeremonyProtector` reicht ihn verschlüsselt an die App weiter.

## D2 Zustand verschlüsselt beim Client

`ITimeLimitedDataProtector` (Zweck `Gainer.Passkeys` + Vorgang) schützt `{UserId, State}` für 5 Minuten. Beim Einlösen prüft der Server Konto und Vorgang und merkt sich den SHA-256 des Tokens im `IMemoryCache` bis zum Ablauf. Damit wird jeder Zustand höchstens einmal angenommen; die API läuft als einzelne Instanz. Ein fremdes Konto verbraucht den Zustand nicht, weil die Kontoprüfung vor dem Merken steht.

## D3 Origin einer nativen App

iOS signiert für Apps mit Associated Domain die Origin `https://<relying party>`. Einen Browser-Origin zum Vergleichen gibt es nicht. `ValidateOrigin` akzeptiert daher genau `https://gainer.markfort.xyz` ohne Cross-Origin. Die Domain kommt aus `Security:Passkeys:ServerDomain` (`appsettings.json`).

## D4 Identity-Schema 3

Identity legt die Passkey-Tabelle nur an, wenn die Store-Optionen Version 3 verlangen, und Design-Time-Tooling kennt diese Optionen nicht. `AppDbContext` mappt `IdentityUserPasskey<Guid>` deshalb selbst, genau wie Identity: Schlüssel `CredentialId` (max. 1024 Byte), Daten als JSON, Fremdschlüssel auf `users` mit Cascade. Die API setzt zusätzlich `Stores.SchemaVersion = Version3`, damit `UserManager` Passkeys unterstützt.

## D5 Widerrufene Tokens

Bisher wies `DeviceSessionValidationMiddleware` jeden Request mit widerrufenem Token mit 401 ab, auch Anmelde-Endpunkte. Jetzt ersetzt sie den Nutzer durch einen anonymen und das Authentifizierungsergebnis durch „kein Ergebnis“. `[Authorize]`-Endpunkte antworten weiterhin mit 401.

## D6 Aufteilung Swift/Dart

Swift baut nur in der CI. `NativePasskeys.swift` liefert deshalb nur Rohbytes: Credential-ID, clientDataJSON, attestationObject bzw. authenticatorData, Signatur und userHandle. Optionen lesen und WebAuthn-JSON bauen macht `PasskeyCeremony` in Dart, mit Unit-Tests. Abbruch im System-Sheet ergibt `null` und ändert nichts.

## D7 Tests

Ein Software-Authenticator in den Integrationstests (P-256, CBOR, `none`-Attestation, Flags UP/UV/BE/BS) erzeugt echte WebAuthn-Antworten mit der Origin, die iOS verwendet. So laufen Registrierung und Anmeldung serverseitig vollständig durch.
