# Seed Box

Seed Box is a native macOS app for managing Stardew Valley mods.

The current build manages Stardew Valley's default `Mods` folder. It does
not launch the game.

## Direction

Seed Box is becoming a sandboxed mod-set manager:

- the default `Mods` folder is the uneditable base inventory
- named mod sets are saved as plist profiles in Application Support
- new mod sets start from the current enabled/disabled state
- applying a set enables or disables mod folders by adding or removing a leading
  period from each folder name
- changes to an editable active set save automatically
- any mod collection can be represented as a set

## Current Build

- Suggests Steam when found:
  `~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods`
- Falls back to GOG app location:
  `/Applications/Stardew Valley.app/Contents/MacOS/Mods`
- Requires the user to choose the `Mods` folder so macOS grants access
- Manages mods in the chosen `Mods` folder
- Adds unzipped mod folders
- Enables/disables mods by adding or removing a leading period
- Moves deleted mods to the Trash
- Stores mod-set plist files in `~/Library/Application Support/Seed Box/Mod Sets`
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

The app target is sandboxed. Seed Box writes its own mod-set data inside the
app container's Application Support directory and uses user-granted access for
the Stardew Valley `Mods` folder.

- choosing the Mods folder stores a security-scoped bookmark
- mod operations require that saved folder access
- mod-set plist files resolve to the container's Application Support directory
  in sandboxed builds

## Project History

Seed Box was split out of an older Platypus-based app wrapper. That generated
bundle is gone; maintained source now lives in this Xcode project.
