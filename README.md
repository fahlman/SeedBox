# Seed Box

Seed Box is a native macOS app for managing SMAPI mods for Stardew Valley.

The current build manages the `Mods-SVE` folder created for the original launcher
work, while the app is being split into its own repo and renamed for the broader
mod-set manager direction.

## Direction

Seed Box is becoming a SMAPI mod-set manager:

- the default SMAPI `Mods` folder is the uneditable base inventory
- named mod sets are saved as plist profiles
- applying a set enables or disables mod folders by adding or removing a leading
  period from each folder name
- "Stardew Valley Expanded" is one possible set, not the app's identity

## Current Build

- Detects the common Steam install path:
  `~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS`
- Launches `StardewModdingAPI --mods-path Mods-SVE`
- Manages mods in the fixed `Mods-SVE` folder
- Adds unzipped mod folders
- Enables/disables mods by adding or removing a leading period
- Moves deleted mods to the Trash
- Captures SMAPI output in the app window
- Keeps install paths and setup actions in Settings

## Requirements

- macOS 13 or newer
- Xcode command line tools for building from source
- Stardew Valley installed on macOS
- [SMAPI](https://smapi.io/) installed into Stardew Valley

## Build

```sh
swift test
scripts/build-app.sh
```

The app bundle is written to:

```text
dist/Seed Box.app
```

The build script ad-hoc signs the app for local use. Release distribution should
use a Developer ID certificate and notarization.

### Optional Sandbox Build

The default build is intentionally not sandboxed, because SMAPI and Stardew mods
expect normal access to the game folder and child processes may inherit sandbox
limits.

The app is sandbox-aware, though:

- choosing the Stardew folder stores a security-scoped bookmark
- file validation, mod-folder creation, symlink setup, and launch all use that
  saved folder access when available
- an experimental sandbox entitlement file is included at
  `Packaging/Sandbox.entitlements`

To produce a sandbox-signed test build:

```sh
SANDBOX=1 scripts/build-app.sh
```

For general releases, use the default build with Developer ID signing and
notarization.

## Legacy App

Seed Box was split out of the old Platypus-based SVE launcher. The old generated
bundle has been removed; maintained source lives under `Sources/`, and generated
app bundles come from `scripts/build-app.sh`.
