# Gainer Mobile

This is the iOS-first Flutter bootstrap. The tabs currently show clearly marked
work-in-progress states; they do not represent completed PWA feature parity.

## Pinned toolchain

`tool/toolchain.json` records the official Flutter stable release, Dart version,
archive SHA-256 values, iOS deployment target and pinned macOS/Xcode runner. The
Windows SDK is cached under the repository's ignored `artifacts/flutter-sdk`
directory and is deliberately separate from any preinstalled Flutter SDK.
CI downloads the matching official macOS archive and verifies its SHA-256
before use. `pubspec.lock` locks all Dart packages.

On Windows, install or extract the pinned Flutter SDK to
`artifacts/flutter-sdk/3.47.7/flutter`, then run:

```powershell
pwsh ./scripts/Verify-Mobile.ps1
```

The script rejects a non-stable channel, another Flutter revision or another
Dart version before resolving packages. It runs Dart formatting, Pigeon code
generation, analysis and widget tests. Add `-BuildIosSimulator` on macOS with
the pinned Xcode installation to include an unsigned simulator build. Windows
cannot build iOS targets.

The shell preview at `artifacts/mobile-preview/mobile-shell-390x844.png` comes
from Flutter's widget-test renderer. Its Ahem test font makes text and icons
appear as blocks, so it is useful only for checking basic layout and spacing;
typography and native appearance require a later simulator or device review.

Drift schemas use the pinned code generator. Regenerate their Dart bindings with
`dart run build_runner build --delete-conflicting-outputs` from `apps/mobile`.

The manual `Mobile CI` dispatch can produce a signed IPA for review without
uploading it to Apple. The `ios-beta` GitHub Environment holds four non-secret
identifier variables: `APPLE_TEAM_ID`, `IOS_BUNDLE_ID`,
`IOS_WIDGET_BUNDLE_ID`, and `IOS_APP_GROUP_ID`. It also requires exactly four
signing secrets: `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`,
`IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`,
and `IOS_WIDGET_PROVISIONING_PROFILE_BASE64`. See the [Apple Developer setup
guide](docs/apple-developer-setup.md) for profile and variable setup. The
non-secret GitHub variables
`GAINER_API_ORIGIN` and `GAINER_TRUSTED_FRONTEND_ORIGIN` may override the
documented deployment origin `https://gainer.markfort.xyz`; both values must
be HTTPS origins without credentials, paths, queries or fragments. The
workflow passes them as Dart defines, and missing or mismatched signing data
fails before archiving. The `ios-beta` environment currently requires manual
review by `PlaySkyHD` and is limited to `main`; no upload to TestFlight or App
Store Connect occurs. The resulting Actions artifact is not a private
distribution channel: repository readers may be able to download the signed
IPA. Never put secrets, provisioning profiles or certificates in the artifact,
and do not request a signed build until its audience and distribution method
are intended.

The app currently handles its private `gainer://` routes. Universal links are
not configured yet. They require the final signed app identifier, an
Associated Domains entitlement, a matching `apple-app-site-association` file
on the existing HTTPS host, and a verified device install/open test before
they can be claimed as supported.

## Architecture boundary

The Cupertino shell is driven by `MobileShellViewModel` and provided with
Provider. Network, persistence and Apple system services belong in injected
services/repositories. Typed platform ports live under
`lib/data/services/platform`; Pigeon schema changes belong in
`pigeons/mobile_platform_api.dart` and generated bindings must be regenerated
with the pinned Pigeon version. The secure-session port has an iOS Keychain
adapter; other native ports and feature journeys remain in progress.

The iOS bridge stores only opaque, API-origin-bound session checkpoints in the
Keychain with `WhenUnlockedThisDeviceOnly` accessibility and iCloud
synchronization disabled. A new app installation clears retained checkpoints.
Passwords and CSRF request tokens are not stored by this bridge.
