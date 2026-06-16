# Release Process

Seed Box ships outside the Mac App Store, so public builds should use Apple's
Developer ID signing and notarization flow.

The release script uses the native Xcode archive and Developer ID export path.
That lets Xcode sign the app bundle, Swift runtime, SwiftPM frameworks, and
entitlements before the script submits the exported app to Apple's notary
service.

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

Use an app-specific password, not the Apple ID account password. Do not commit
notary credentials, app-specific passwords, exported certificates, or keychain
files.

## Build A Release ZIP

Run the full release flow:

```sh
SEEDBOX_NOTARY_PROFILE=seedbox-notary Scripts/release-zip.zsh
```

The full flow uploads the zipped app bundle to Apple's notarization service.
That upload is required for Developer ID notarization.

For a Developer ID export check without submitting to Apple:

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
