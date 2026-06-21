# Seed Box Store Readiness Matrix

This matrix tracks current and planned Seed Box features against likely Mac App
Store and Steam Store viability. It is a validation guide, not a reason to
remove features before review. Implementation work belongs in feature issues;
store validation belongs in GitHub issues labeled `store-readiness`.

Legend:

- **Yes**: Expected to be viable for that store.
- **Risky**: Technically possible, but may trigger storefront review, sandbox,
  policy, or support concerns.
- **No/Risky**: Likely not viable as a dependable store feature.
- **No**: Not applicable or not worth attempting for that store.
- **Depends**: Wait for actual App Review, Steam review, or product decisions.

| Feature | Apple App Store | Steam Store |
|---|---:|---:|
| **Have:** Scan user-selected Mods folder | Yes | Yes |
| **Have:** Security-scoped folder access / sandbox-safe bookmarks | Yes | Yes, optional |
| **Have:** Enable/disable mods | Risky | Yes |
| **Have:** Mod Sets | Yes | Yes |
| **Have:** Apply Mod Sets by changing mod folders | Risky | Yes |
| **Have:** Drag/drop ZIP and folder install | Risky | Yes |
| **Have:** Multi-install ZIPs/folders | Risky | Yes |
| **Have:** Install preview before applying changes | Yes | Yes |
| **Have:** Update/reinstall/downgrade detection | Yes | Yes |
| **Have:** Archive replaced/deleted mods | Yes | Yes |
| **Have:** Restore archived mods | Yes | Yes |
| **Have:** Dependency warnings | Yes | Yes |
| **Have:** Missing dependency reporting | Yes | Yes |
| **Have:** SMAPI update checks for mods | Yes | Yes |
| **Have:** Open mod pages from update results | Yes | Yes |
| **Have:** SMAPI log reading | Yes | Yes |
| **Have:** Last-session problem summaries | Yes | Yes |
| **Have:** Problem-mod bisection | Risky | Yes |
| **Have:** Audit trail | Yes | Yes |
| **Have:** MetricKit diagnostics | Yes | Yes |
| **Planned:** Mod Set export/import | Yes | Yes |
| **Planned:** Profile-specific mod config snapshots | Risky | Yes |
| **Planned:** Per-mod notes | Yes | Yes |
| **Planned:** `.7z` / `.rar` import support | Risky | Yes |
| **Planned:** Launch Stardew/SMAPI | Risky | Yes |
| **Planned:** Detect Steam Stardew install | Yes | Yes |
| **Planned:** Help configure SMAPI launch options | Risky | Yes |
| **Planned:** Automatically configure Steam launch options | No/Risky | Yes |
| **Planned:** SMAPI install/update assistant | Yes, manual/guided | Yes |
| **Planned:** Automatic SMAPI install/update | No/Risky | Yes |
| **Planned:** Nexus mod page lookup | Yes | Yes |
| **Planned:** Nexus API login | Risky | Yes |
| **Planned:** Nexus thumbnails/metadata | Risky | Yes |
| **Planned:** NXM link handling | No/Risky | Yes |
| **Planned:** Direct Nexus downloads | No/Risky | Yes |
| **Planned:** Nexus update-all automation | No/Risky | Yes |
| **Planned:** Steamworks integration | No | Yes |
| **Planned:** Store-specific availability messaging if App Review rejects a required feature | Depends | Yes |

## Verified Have Features

- 2026-06-20: MetricKit diagnostics are local-only, support user-initiated ZIP
  export, and have no known App Store or Steam-specific constraint. Verified
  with full `Seed Box` and `Seed Box Steam` scheme test runs.
- 2026-06-20: Audit trail entries are stored locally in Application Support,
  surfaced in the Activity sheet, and have no known App Store or Steam-specific
  constraint. Verified with full `Seed Box` and `Seed Box Steam` scheme test
  runs.
- 2026-06-20: Problem-mod bisection is user-initiated, persists its session, and
  restores the original enabled states when the search ends or is cancelled. Its
  App Store status remains Risky because it temporarily renames mod folders as a
  troubleshooting workflow, but no build-specific code constraint was found.
  Verified with full `Seed Box` and `Seed Box Steam` scheme test runs.
- 2026-06-20: Last-session problem summaries are derived from the user-approved
  SMAPI log folder, filtered to currently installed mods, and refreshed on app
  launch and activation. No App Store or Steam-specific constraint was found.
  Verified with full `Seed Box` and `Seed Box Steam` scheme test runs.
- 2026-06-20: SMAPI log reading uses an explicit user-selected ErrorLogs folder
  bookmark, reads only `SMAPI-latest.txt`, and applies a 64 MB size cap before
  parsing. No App Store or Steam-specific constraint was found. Verified with
  full `Seed Box` and `Seed Box Steam` scheme test runs.
- 2026-06-20: Update results expose mod pages through native SwiftUI links after
  the SMAPI client filters out non-HTTPS URLs. No App Store or Steam-specific
  constraint was found. Verified with full `Seed Box` and `Seed Box Steam`
  scheme test runs.
- 2026-06-20: SMAPI update checks are opt-in, use a fixed HTTPS endpoint with
  an ephemeral URL session, and send only each mod's unique ID, installed
  version, update keys, plus detected SMAPI version when available. The
  sandboxed build includes the network client entitlement. No App Store or
  Steam-specific constraint was found. Verified with full `Seed Box` and
  `Seed Box Steam` scheme test runs.
- 2026-06-20: Missing dependency reporting is derived from installed mod
  manifests, distinguishes required and optional dependency problems, and is
  surfaced in Problems and Smart Mod Sets. No App Store or Steam-specific
  constraint was found. Verified with full `Seed Box` and `Seed Box Steam`
  scheme test runs.
- 2026-06-20: Dependency warnings run before enabling mods with unsatisfied
  required dependencies, disabling mods required by enabled dependents, and
  applying mod sets that would create unresolved required dependencies. No App
  Store or Steam-specific constraint was found. Verified with full `Seed Box`
  and `Seed Box Steam` scheme test runs.

## Release Decision Rule

Seed Box should not be reduced to fit a storefront. Submit the full App Store
candidate unless there is a clear, confirmed policy blocker. If a required
full-product feature is rejected by the Mac App Store and there is no
full-quality, user-honest implementation for that store, Seed Box should ship on
Steam/direct instead of shipping a weakened App Store version.

Potentially required features that would be App Store showstoppers if rejected:

- Enable/disable mods.
- Install/update from user-provided ZIPs or folders.
- Mod Sets.
- Archive/restore.
- SMAPI troubleshooting.
- Any future feature that becomes essential to the product promise.
