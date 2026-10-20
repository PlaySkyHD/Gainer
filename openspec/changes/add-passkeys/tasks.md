# Tasks

## 1. Backend

- [x] 1.1 Identity-Schema 3 und Migration `AddUserPasskeys` (D4).
- [x] 1.2 `PasskeyCeremonyProtector`, `PasskeysController`, `DeviceSignIn`, Origin-Prüfung (D1–D3).
- [x] 1.3 Widerrufene Tokens als anonym behandeln (D5).
- [x] 1.4 Integrationstests mit Software-Authenticator (D7).

## 2. Domain und iOS

- [x] 2.1 `apple-app-site-association` im Edge, CI-Smoke-Test.
- [x] 2.2 Entitlement, `NativePasskeys.swift`, Pigeon-Methoden, Profilprüfung im Workflow (D6).
- [ ] 2.3 Associated Domains im Apple-Portal aktivieren, App-Profil neu erzeugen, Secret ersetzen (Betreiber).

## 3. App

- [x] 3.1 `PasskeyCeremony`, API-Aufrufe, `ApiSessionService`, Controller.
- [x] 3.2 Login-Button und „Mehr → Passkeys“; Goldens und Tests.

## 4. Abschluss

- [ ] 4.1 Production-Deploy, AASA öffentlich prüfen, TestFlight; auf dem iPhone Passkey anlegen, abmelden, mit Face ID anmelden.
