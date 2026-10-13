# Gainer Mobile

This is the iOS-first Flutter bootstrap. The tabs currently show clearly marked
work-in-progress states; they do not represent completed PWA feature parity.

## Pinned toolchain

`tool/toolchain.json` records the official Flutter stable release, Dart version,
archive SHA-256 values, iOS deployment target and pinned macOS/Xcode runner. The
Windows SDK is cached under the repository's ignored `artifacts/flutter-sdk`
directory and is deliberately separate from any preinstalled Flutter SDK.
CI runs on GitHub's `macos-15` runner, currently an Apple Silicon ARM64 image,
and downloads the official ARM64 archive for the same Flutter 3.47.7 revision
and Dart 3.13.5 used by the Windows SDK. It verifies the archive SHA-256 and
checks the runner architecture before use, avoiding Rosetta translation. CI
still runs the same doctor, analysis, tests, simulator build and native tests.
`pubspec.lock` locks all Dart packages.

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

Mobile CI caches the official macOS Flutter SDK archive and only the public
`pub.dev` package and hash directories. Cache keys include the runner OS and
architecture plus the pinned toolchain; the Dart package key also includes the
mobile manifest and lockfile. The SDK archive SHA-256 is checked whether it
comes from cache or a fresh download, and `pub get --enforce-lockfile` plus all
analysis, tests and builds still run. Cache restore/save is time-limited and
non-blocking, so a miss or cache-service failure falls back to a normal clean
download and dependency restore. This iOS project has no tracked CocoaPods or
Swift Package lockfile, so CI does not cache Pods, derived data or build
outputs. The simulator job populates these caches; the signed job restores them
before loading signing materials and does not save cache entries. No runtime
speedup has been measured yet. Signed manual runs use a separate concurrency
group from automatic verification runs, so a cache or verification update does
not cancel an in-progress signed build.

The shell preview at `artifacts/mobile-preview/mobile-shell-390x844.png` comes
from Flutter's widget-test renderer. Its Ahem test font makes text and icons
appear as blocks, so it is useful only for checking basic layout and spacing;
typography and native appearance require a later simulator or device review.

Drift schemas use the pinned code generator. Regenerate their Dart bindings with
`dart run build_runner build --delete-conflicting-outputs` from `apps/mobile`.

The manual `Mobile CI` dispatch can produce a signed IPA for review, or upload
it to App Store Connect for TestFlight processing when `upload_testflight` is
explicitly enabled. That option implies a signed build, stays behind the
`ios-beta` environment approval and successful simulator gate, and does not
submit the app for public App Review or invite testers. The `ios-beta` GitHub
Environment holds four non-secret identifier variables: `APPLE_TEAM_ID`, `IOS_BUNDLE_ID`,
`IOS_WIDGET_BUNDLE_ID`, and `IOS_APP_GROUP_ID`. It also requires exactly four
signing secrets: `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`,
`IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`,
and `IOS_WIDGET_PROVISIONING_PROFILE_BASE64`. TestFlight additionally needs
the three Environment secrets `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_PRIVATE_KEY`; these are
read only when an upload is explicitly requested. See the [Apple Developer setup
guide](docs/apple-developer-setup.md) for profile and variable setup. The
non-secret GitHub variables
`GAINER_API_ORIGIN` and `GAINER_TRUSTED_FRONTEND_ORIGIN` may override the
documented deployment origin `https://gainer.markfort.xyz`; both values must
be HTTPS origins without credentials, paths, queries or fragments. The
workflow passes them as Dart defines, and missing or mismatched signing data
fails before archiving. Runner and widget share the marketing version from
`pubspec.yaml` and a default build number from the workflow run and attempt.
The `ios-beta` environment currently requires manual review by `PlaySkyHD` and
is limited to `main`. Signed-IPA-only mode creates an Actions artifact that is
not a private distribution channel: repository readers may be able to download
the signed IPA. Never put secrets, provisioning profiles or certificates in
the artifact, and do not request an IPA-artifact build until its audience and
distribution method are intended. TestFlight mode does not attach the IPA;
Apple processing and manual tester assignment still follow the upload.

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
