# Seed Box Roadmap

This file tracks planned work that should not live only in chat history. It is
not a release promise; it is a shared checklist for choosing the next focused
task.

## Current Priority

### Release trust and updates

- Build the full product first; do not remove features from the App Store
  candidate based only on guessed review outcomes.
- Keep one codebase with separate sandboxed App Store-candidate and
  non-sandboxed Steam release builds.
- Prepare the App Store and Steam release paths in parallel so either channel can
  ship the same product promise.
- Keep the Developer ID ZIP release script available for Steam packaging,
  direct-download testing, and notarization checks.
- Confirm Gatekeeper behavior for Steam and any direct-download app archive.
- Use GitHub issues labeled `store-readiness` for store validation and
  storefront-specific decisions; keep feature implementation work in the
  feature issues.

## Next Product Features

### Smart Mod Sets

Smart Mod Sets are saved searches. They are not manually edited by adding or
removing mods; users edit the search/rule that defines the set.

- Add built-in Smart Mod Sets for common searches.
- Let users save the current search as a Smart Mod Set.
- Let users rename, edit, duplicate, and delete user-created Smart Mod Sets.
- Reuse the existing search parser first.
- Consider a native AppKit `NSPredicateEditor` rule builder later if plain
  search text becomes too limiting.

Example Smart Mod Sets:

- SMAPI Mods
- Content Patcher Mods
- Updates Available
- Errors
- Warnings
- Disabled Mods

### Dependent mod sets

Allow a regular Mod Set to inherit from another regular Mod Set, so a player can
start with a baseline set and layer optional collections on top.

- Store parent relationships by stable set ID.
- Detect and prevent cycles.
- Resolve chains such as C inherits B inherits A.
- Make inherited state clear in the sidebar and main table.
- Keep Smart Mod Sets separate from inheritance because they are saved searches,
  not enable/disable configurations.

## Product Polish

- Create a real app icon.
- Finish the About box and credits review before public release.
- Keep improving Help content as workflows settle.
- Review notification permission timing; prefer asking when the feature becomes
  relevant instead of automatically at launch.
- Do a hands-on accessibility pass with VoiceOver and keyboard navigation.
- Add visible diagnostics/export support if support conversations need it.

## Release Discipline

- Decide the versioning policy before the first public release.
- Keep `MARKETING_VERSION`, build numbers, App Store Connect versions, and
  release tags in lockstep.
- Discuss continuous integration after the release path is clearer.
- Keep full test-suite verification as the default checkpoint before pushing
  behavior changes.
