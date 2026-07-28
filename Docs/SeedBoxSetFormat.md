# `.seedboxset` File Format

A portable, versioned representation of a Mod Set, used for backup, sharing, and
transferring Mod Sets between Macs. Defined by `SeedBoxSetDocument` /
`SeedBoxSetCodec` in `SeedBox/Core/SeedBoxSetDocument.swift`.

This format is the foundation for native document opening (#105), sharing (#45),
Quick Look previews (#46), and document icons (#102).

## Identity

- **Extension:** `.seedboxset`
- **Content type identifier:** `com.fahlsing.seedbox.modset` (registered with the
  system in #105)
- **Encoding:** UTF-8 JSON, pretty-printed with sorted keys.

## Schema (version 1)

```json
{
  "schemaVersion": 1,
  "kind": "modSet",
  "generator": "Seed Box",
  "modSet": {
    "name": "My Set",
    "disabledMods": [
      {
        "folderName": "ContentPatcher",
        "modName": "Content Patcher",
        "uniqueID": "Pathoschild.ContentPatcher",
        "version": "2.0.0"
      }
    ]
  }
}
```

### Fields

- `schemaVersion` (Int, required) — the schema this file was written with.
- `kind` (String, required) — always `modSet`. Reserved for future document
  kinds (e.g. saved searches).
- `generator` (String) — informational; the app that wrote the file.
- `modSet.name` (String, required, non-empty) — the Mod Set's display name.
- `modSet.disabledMods` (Array) — the mods this set disables. Each entry:
  - `folderName` (String, required) — canonical folder name (no leading dot).
    Used to match the mod on the receiving Mac.
  - `modName`, `uniqueID`, `version` (String, optional) — manifest metadata
    captured at export time so a receiving Mac can explain a missing mod without
    needing the mod itself.

A Mod Set's *enabled* mods are implied: any installed mod not listed in
`disabledMods` is enabled. An inheriting Mod Set should be exported from its
fully resolved disabled list, so it travels as a self-contained regular set.

## Versioning

- `currentSchemaVersion` is what this build writes; `minimumSupportedSchemaVersion`
  is the oldest it can read.
- **Older** than supported → rejected (`unsupportedVersion`).
- **Newer** than this build → rejected with a clear "update Seed Box" message
  (`futureVersion`). Version and `kind` are validated from a minimal envelope
  before the full decode, so a future file is reported cleanly even if its
  structure changed.
- **Same** version with unknown extra fields → accepted; unknown fields are
  ignored (forward compatible).

## Intentionally excluded (privacy & security)

Imported files are treated as untrusted input, and exports never contain:

- actual mod folder contents
- archived mods
- mod config files
- logs or diagnostics
- security-scoped bookmarks
- absolute local paths or other machine-specific access data

Import validates schema version and content before any app-state change, and
imported sets are never auto-applied.
