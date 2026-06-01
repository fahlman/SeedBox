# Seed Box

Seed Box is a native macOS app for managing Stardew Valley mods.

The current build manages Stardew Valley's default `Mods` folder. It does
not launch the game.

## Direction

Seed Box is becoming a mod-set manager:

- the default `Mods` folder is the uneditable base inventory
- named mod sets are saved as plist profiles
- applying a set enables or disables mod folders by adding or removing a leading
  period from each folder name
- "Stardew Valley Expanded" is one possible set, not the app's identity

## Current Build

- Defaults to:
  `~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods`
- Manages mods in the default `Mods` folder
- Adds unzipped mod folders
- Enables/disables mods by adding or removing a leading period
- Moves deleted mods to the Trash
- Keeps mods-folder path and setup actions in Settings

## Requirements

- macOS 13 or newer
- Xcode 15 or newer
- Stardew Valley installed on macOS

## Build

Open `SeedBox.xcodeproj` in Xcode and run the **Seed Box** scheme.

Command line verification:

```sh
xcodebuild -project SeedBox.xcodeproj -scheme "Seed Box" -destination "platform=macOS" test
```

The project uses ad-hoc signing for local Debug/Release builds. Release
distribution should use a Developer ID certificate and notarization.

## Sandbox Notes

The default app target is intentionally not sandboxed while the mod-management
workflow settles, because Stardew mods live inside the game install folder.

The app is sandbox-aware, though:

- choosing the Mods folder stores a security-scoped bookmark
- file validation, mod-folder creation, and mod operations use that saved folder
  access when available
- `SeedBox/Sandbox.entitlements` is included as a starting point for a future
  sandbox experiment

## Legacy App

Seed Box was split out of the old Platypus-based SVE launcher. The old generated
bundle has been removed; maintained source now lives in this Xcode project.
