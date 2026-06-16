# Release Process

Seed Box ships outside the Mac App Store, so public builds should use Apple's
Developer ID signing and notarization flow.

Seed Box's release path is built on Apple's native distribution tools:

- Xcode Organizer for manual releases and first-time account setup checks.
- `xcodebuild archive` and `xcodebuild -exportArchive` for repeatable release
  automation.
- `notarytool`, `stapler`, and `spctl` for notarization, ticket stapling, and
  Gatekeeper assessment.

The release script keeps that flow repeatable. It lets Xcode sign the app
bundle, Swift runtime, SwiftPM frameworks, and entitlements before submitting
the exported app to Apple's notary service.

## Prerequisites

- Apple Developer Program membership for team `PUT2KYMV2W`.
- A valid **Developer ID Application** certificate installed in the login
  keychain.
- Xcode signed in to the Apple ID that can use that team.
- A `notarytool` keychain profile or notary credentials supplied through
  environment variables.

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

## Native Xcode Flow

Use this path first when setting up Developer ID signing on a new Mac:

1. Open `SeedBox.xcodeproj`.
2. Choose the **Seed Box** scheme.
3. Choose **Product > Archive**.
4. In Organizer, choose **Distribute App**.
5. Choose **Developer ID** distribution.
6. Let Xcode sign and notarize the app.

This is the clearest way to confirm the Apple ID, team, certificate, and Xcode
account setup are healthy.

## Automated Release ZIP

Use this path for repeatable releases after the native Xcode flow works.

Run the full release flow:

```sh
SEEDBOX_NOTARY_PROFILE=seedbox-notary Scripts/release-zip.zsh
```

The full flow uploads the zipped app bundle to Apple's notarization service.
That upload is required for Developer ID notarization.

For a Developer ID export and packaging check without submitting to Apple:

```sh
Scripts/release-zip.zsh --skip-notarization
```

The script writes release artifacts to `dist/`, which is ignored by Git:

- `SeedBox-<version>.zip`
- `SeedBox-<version>-manifest.json`

The manifest records the version, build number, bundle identifier, team ID,
archive path, ZIP path, SHA-256 hash, and whether the ZIP was notarized.

## Verification

The full release flow verifies:

- the app is signed by a Developer ID Application certificate for the expected
  team;
- the sandbox, security-scoped bookmark, user-selected file access, and network
  client entitlements are present;
- debug signing entitlements are absent;
- the executable is universal (`arm64` and `x86_64`);
- notarization succeeds;
- the notarization ticket staples and validates;
- Gatekeeper accepts the stapled app;
- Gatekeeper accepts the final ZIP after local quarantine extraction.

After the first hosted release artifact exists, also download the ZIP from the
same place users will download it and open the app from `~/Downloads`. That is
the real end-to-end Gatekeeper check.
