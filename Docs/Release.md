# Release Process

Seed Box uses one codebase with separate release builds for the Mac App Store
candidate and Steam. The App Store candidate remains sandboxed. The Steam build
uses the same app target and source files, but archives with Steam-compatible
signing settings and no App Sandbox entitlement.

Seed Box's release path is built on Apple's native distribution tools:

- Xcode Organizer and App Store Connect for Mac App Store uploads.
- Xcode Organizer for first-time account, certificate, and distribution checks.
- `xcodebuild archive` and `xcodebuild -exportArchive` for repeatable Developer
  ID and Steam packaging automation.
- `notarytool`, `stapler`, and `spctl` for Steam and optional direct-download
  notarization, ticket stapling, and Gatekeeper assessment.

The Developer ID release script keeps the Steam and optional direct-download
flows repeatable. It lets Xcode sign the app bundle, Swift runtime, SwiftPM
frameworks, and entitlements before submitting the exported app to Apple's
notary service.

## Release Principle

Seed Box should submit the full App Store candidate unless there is a clear,
confirmed policy blocker. Do not remove features from the App Store build based
only on guessed review outcomes. If App Review rejects a required full-product
feature, record the exact objection and decide whether the App Store build can
remain a full-quality product or whether Steam/direct distribution is the better
channel.

## Versioning Discipline

Seed Box uses one public version and one monotonically increasing build number
across all distribution channels.

- `MARKETING_VERSION` is the public app version. Use semantic versioning in the
  form `major.minor.patch`.
- `CURRENT_PROJECT_VERSION` is the build number. Use a whole number and increase
  it for every App Store upload, Steam release candidate, notarized ZIP, or
  other build handed to someone outside local development.
- The App Store-candidate build and Steam build for the same product release use
  the same `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Channel differences
  belong in schemes, build configurations, entitlements, signing, packaging, and
  store metadata, not in the version number.
- Never reuse the same `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` pair for
  two different release artifacts.

Before archiving for release, the person making the release updates
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `SeedBox.xcodeproj` for all
Seed Box app configurations. The version bump should be its own commit or an
obvious part of the release-preparation commit.

App Store Connect versions map directly to `MARKETING_VERSION`. Final Git tags
use `v<MARKETING_VERSION>` and point at the commit used for the public release.
For example, App Store version `1.0.0` uses tag `v1.0.0`. Do not move final
release tags after publishing them. If release-candidate tags are useful before
the public release, use `v<MARKETING_VERSION>-rc.<number>`; those tags do not
represent App Store Connect versions.

## Prerequisites

- Apple Developer Program membership for team `PUT2KYMV2W`.
- Xcode signed in to the Apple ID that can use that team.
- An App Store Connect app record before the first Mac App Store upload.
- A valid **Developer ID Application** certificate for Steam and optional
  direct-download builds.
- A `notarytool` keychain profile or notary credentials for Steam and optional
  direct-download notarization.

Create the local notary profile once:

```sh
xcrun notarytool store-credentials seedbox-notary \
  --apple-id "you@example.com" \
  --team-id PUT2KYMV2W \
  --password "app-specific-password"
```

Use an app-specific password for notarization. Keep notary credentials,
app-specific passwords, exported certificates, and keychain files in Keychain or
secret storage outside the repository.

## Mac App Store Flow

Use this path for a sandboxed App Store submission candidate:

1. Open `SeedBox.xcodeproj`.
2. Choose the **Seed Box** scheme.
3. Confirm `MARKETING_VERSION` matches the App Store Connect version being
   uploaded.
4. Confirm `CURRENT_PROJECT_VERSION` is greater than every build number already
   uploaded for that App Store Connect version.
5. Choose **Product > Archive**.
6. In Organizer, choose **Distribute App**.
7. Choose **App Store Connect** distribution.
8. Upload the archive and finish release setup in App Store Connect.

The App Store handles public update delivery for this distribution path.

## Steam Flow

Use this path for the Steam-compatible macOS build:

1. Open `SeedBox.xcodeproj`.
2. Choose the **Seed Box Steam** scheme.
3. Confirm `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` match the App Store
   candidate for the same product release.
4. Choose **Product > Archive**.
5. In Organizer, choose **Distribute App**.
6. Choose **Developer ID** distribution.
7. Let Xcode sign and notarize the app.

The Steam scheme uses `Release Steam`, `SeedBox/Steam.entitlements`, hardened
runtime, and `ENABLE_APP_SANDBOX = NO`. The normal **Seed Box** scheme continues
to use `SeedBox/Sandbox.entitlements` for the App Store candidate.

## Automated Developer ID ZIP

Use this path for repeatable Steam packaging and optional direct-download builds
after the Developer ID flow works.

Run the full release flow:

```sh
SEEDBOX_NOTARY_PROFILE=seedbox-notary Scripts/release-zip.zsh
```

Run the Steam-compatible release flow:

```sh
SEEDBOX_NOTARY_PROFILE=seedbox-notary Scripts/release-zip.zsh --steam
```

The full flow uploads the zipped app bundle to Apple's notarization service.
That upload is required for Developer ID notarization before Steam distribution.

For a Developer ID export and packaging check without submitting to Apple:

```sh
Scripts/release-zip.zsh --skip-notarization
Scripts/release-zip.zsh --steam --skip-notarization
```

The script writes release artifacts to `dist/`, which is ignored by Git:

- `SeedBox-<version>.zip`
- `SeedBox-<version>-manifest.json`
- `SeedBox-Steam-<version>.zip`
- `SeedBox-Steam-<version>-manifest.json`

The manifest records the version, build number, bundle identifier, team ID,
archive path, ZIP path, SHA-256 hash, and whether the ZIP was notarized.

## Verification

The full release flow verifies:

- the archive reports the intended `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION`;
- the app is signed by a Developer ID Application certificate for the expected
  team;
- the App Store-candidate build includes the sandbox, security-scoped bookmark,
  user-selected file access, and network client entitlements;
- the Steam build omits the App Sandbox entitlement and includes Steam's
  hardened-runtime compatibility entitlements;
- direct Downloads folder access is absent because imports use user-selected
  file access;
- debug signing entitlements are absent;
- the executable is universal (`arm64` and `x86_64`);
- notarization succeeds;
- the notarization ticket staples and validates;
- Gatekeeper accepts the stapled app;
- Gatekeeper accepts the final ZIP after local quarantine extraction.

After the first hosted release artifact exists, also download the ZIP from the
same place users will download it and open the app from `~/Downloads`. That is
the real end-to-end Gatekeeper check.
