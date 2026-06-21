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
- Archives deleted or replaced mods in searchable Restore History so previous
  versions can be restored or permanently removed.
- Watches the Mods folder and reconciles changes made outside the app.
- Records an audit trail for mod and mod-set actions.
- Can opt in to SMAPI mod update checks through `api.smapi.io`.
- Can read SMAPI's latest log, surface last-session mod problems, and start
  problem-mod bisection.
- Stores and exports local-only MetricKit diagnostic payloads for crash-awareness support.
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
- MetricKit diagnostic payloads in `Application Support/Seed Box/Diagnostics`

The selected Stardew Valley `Mods` folder remains the only place Seed Box puts
active mods.

## Sandbox

The app target is sandboxed and uses:

- app-scoped security bookmarks
- user-selected read/write file access
- network client access for optional SMAPI update checks

The user must choose the Stardew Valley `Mods` folder before Seed Box can manage
mods there. Seed Box does not request direct Downloads folder access; imports
use user-selected file access instead.

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

Runtime:

- macOS 15.6 or newer
- Stardew Valley for macOS

Development:

- Xcode 26 or newer
- Swift 6

## Build And Test

Open `SeedBox.xcodeproj` in Xcode and run the **Seed Box** scheme for the
sandboxed App Store candidate, or **Seed Box Steam** for the Steam-compatible
build.

Command-line verification:

```sh
xcodebuild test -project SeedBox.xcodeproj -scheme "Seed Box" -destination "platform=macOS"
```

Local builds use the project signing settings. Public distribution is planned
around one codebase with separate App Store-candidate and Steam release builds.
The App Store candidate should stay the full product unless a confirmed review
or policy blocker requires a channel-specific decision.

## Development Workflow

Seed Box uses feature branches and pull requests for meaningful changes. Keep
`main` stable, avoid a permanent `develop` branch, and squash merge completed
pull requests.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Release

Seed Box keeps one codebase and two release builds: a sandboxed Mac App Store
candidate and a non-sandboxed Steam-compatible Developer ID build.

See [Docs/Release.md](Docs/Release.md).

Store-specific release validation is tracked in
[Docs/StoreFeatureMatrix.md](Docs/StoreFeatureMatrix.md) and GitHub issues
labeled `store-readiness`.

## Roadmap

Planned release work and larger feature ideas live in [ROADMAP.md](ROADMAP.md).

## Third-Party Notices

Open-source dependency notices live in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
