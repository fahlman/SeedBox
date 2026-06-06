# Seed Box

Seed Box is a native SwiftUI macOS app for managing Stardew Valley mods and
mod sets. It manages the selected Stardew Valley `Mods` folder; it does not
launch the game.

## Current App

- Detects the usual Steam and GOG Stardew Valley `Mods` locations.
- Uses a user-selected `Mods` folder with a security-scoped bookmark for
  sandbox-safe access.
- Scans installed mods from the folder that contains each `manifest.json`.
- Lists mods in a sortable table with state, mod name/version, author, type,
  description, and dependency information.
- Supports search filters such as column-style queries.
- Enables or disables mods by adding or removing a leading period from the mod
  folder name.
- Adds mods from folders or ZIP archives, including archives that contain
  multiple mod folders.
- Previews installs, updates, reinstalls, downgrades, duplicates, and skipped
  items before applying them.
- Archives deleted or replaced mods so previous versions can be restored.
- Watches the Mods folder and reconciles changes made outside the app.
- Records an audit trail for mod and mod-set actions.
- Includes localized app strings in the string catalog.

## Mod Sets

Seed Box stores mod-set plist files in Application Support, not inside the
Stardew Valley `Mods` folder.

Included mod sets:

- `All`: generated from the installed mod inventory with every mod enabled.
- `None`: generated from the installed mod inventory with every mod disabled.
- `Default`: included baseline set.

Included sets cannot be edited, renamed, or deleted. User-created sets can be
created, duplicated, renamed, deleted, and updated in real time while active.
When a user-created set is active, mod state changes are saved back to that set.

Applying a set updates the physical mod folders in the selected `Mods` folder.

## Dependency Handling

Seed Box uses dependency data declared in each mod's `manifest.json`.

- Missing required and optional dependencies are surfaced in the UI.
- Disabling a mod can warn when another enabled mod depends on it.
- Enabling a mod can warn when its required dependencies are missing, disabled,
  or too old.
- Applying a mod set can warn when the set would create dependency problems.

Seed Box does not maintain custom compatibility rules for mods that omit or
misdeclare dependency metadata.

## Storage

In a sandboxed build, Application Support resolves inside the app container.
Seed Box stores:

- mod-set plists in `Application Support/Seed Box/Mod Sets`
- archived deleted/replaced mods in `Application Support/Seed Box/Archived Mods`
- the audit log at `Application Support/Seed Box/Audit Log.plist`

The selected Stardew Valley `Mods` folder remains the only place Seed Box puts
active mods.

## Sandbox

The app target is sandboxed and uses:

- app-scoped security bookmarks
- user-selected read/write file access

The user must choose the Stardew Valley `Mods` folder before Seed Box can manage
mods there.

## Project Layout

- `SeedBox/App`: app entry point, window scene, commands
- `SeedBox/Core`: domain models and mod library logic
- `SeedBox/Localization`: string accessors
- `SeedBox/Presentation`: view model, presentation state, command context
- `SeedBox/Services`: file access, mod manager service, audit, monitoring
- `SeedBox/State`: persisted preferences and app state
- `SeedBox/Views`: SwiftUI views
- `SeedBox/Resources`: string catalog and resources
- `SeedBoxTests`: unit tests

## Requirements

- macOS 15.6 or newer
- Xcode 16 or newer
- Swift 6
- Stardew Valley for macOS

## Build And Test

Open `SeedBox.xcodeproj` in Xcode and run the **Seed Box** scheme.

Command-line verification:

```sh
xcodebuild test -project SeedBox.xcodeproj -scheme "Seed Box" -destination "platform=macOS"
```

Local builds use the project signing settings. Distribution should use a
Developer ID certificate and notarization.
