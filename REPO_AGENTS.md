# Seed Box — Repository Instructions

Read the shared `AGENTS.md` first, then `README.md` and `CONTRIBUTING.md`.

## Product and architecture

- Seed Box manages Stardew Valley mods and mod sets; it does not launch the game.
- `SeedBox/Core` owns domain and library logic; `Services` owns filesystem
  access and monitoring; `Presentation` and `Views` present that state.
  `State` holds preferences; `Resources` holds the string catalog.
- The user-selected Mods folder is the only active mod location. Preserve
  security-scoped access, preview-before-apply behavior, Restore History, and
  the audit trail for installs, updates, replacement, and removal.
- Enable or disable a mod through its folder name. Derive dependencies from
  `manifest.json`; do not invent compatibility rules for undeclared dependencies.
- Store mod-set plists and archived mods in Application Support, not the Mods
  folder. Included All, None, and Default sets cannot be edited, renamed, or
  deleted. Active user-created sets track user changes.
- Network update checks are optional; diagnostics remain local unless the user
  exports them. Tests should use fixture folders, not a real game installation.

## Verification and releases

- Use `SeedBox.xcodeproj`, scheme `Seed Box`, and the existing `SeedBoxTests`.
  The documented Swift check is:

  ```sh
  xcodebuild test -project SeedBox.xcodeproj -scheme "Seed Box" -destination "platform=macOS"
  ```

- Squash-merge completed work into `main`; there is no permanent develop branch.
- Read `Docs/Release.md` and `Docs/StoreFeatureMatrix.md` for distribution work.
  `Seed Box` is the sandboxed App Store candidate; `Seed Box Steam` uses the same
  code with Steam-compatible signing. Keep the full product in both unless a
  confirmed blocker warrants an authorized difference.
- Keep release versions and build numbers coordinated across channels, preserve
  signing and entitlement boundaries, and verify the exported artifact using
  the release procedure. Release scripts can upload for notarization; invoking
  them is distinct from running ordinary tests.

## Toolchain and platforms

Settings inspected on 2026-09-25 in `SeedBox.xcodeproj/project.pbxproj`.

- Selected local tools: Xcode 27.0 (`27A266a`), Apple Swift 6.4
  (`swiftlang-6.4.0.34.1`). These exact versions are not pinned by the project.
- Swift language mode: 6.0 (`SWIFT_VERSION`) for all Swift targets.
- SDK: `SDKROOT = macosx`, with no SDK version pin; the selected macOS SDK is 27.0.
- Deployment targets: macOS 15.6 for the app and tests, including Steam configurations.

The selected local tools are a dated snapshot. Existing project settings describe
current configuration; they do not override the shared latest-stable policy.
Handle upgrades as separate tasks.
