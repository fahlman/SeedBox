# System Integration Entities

`SeedBoxEntity` is the one shared vocabulary for Seed Box objects exposed to
macOS system integrations — Spotlight, App Shortcuts, the (future) menu bar,
Finder services, and notifications. A Mod Set has a single identity everywhere,
not one per surface. Defined in `SeedBox/Presentation/SeedBoxEntity.swift`.

## Identity

Every entity has a stable, namespaced `systemIdentifier`:

```
seedbox:<kind>:<rawIdentifier>
```

- `kind` ∈ `mod`, `modSet`, `builtInSmartModSet`, `userSmartModSet`, `destination`
- `rawIdentifier` is the object's natural id (mod/set id, built-in smart-set raw
  value, user smart-set id, or a fixed destination key)

Identifiers are reproducible from state, so reindexing never creates duplicates.
`SeedBoxEntityCatalog.route(forSystemIdentifier:)` maps an identifier back to a
`SeedBoxRoute`; whether the target still exists is the route dispatcher's job
(it returns `.unavailable` for a stale id), so deleted objects fail gracefully.

## Entities

| Kind | rawIdentifier | Route | Default surfaces |
| --- | --- | --- | --- |
| `mod` | mod id | `.mod(id:)` | Spotlight, menu bar |
| `modSet` | set id | `.modSet(id:)` | Spotlight, Shortcuts, menu bar |
| `builtInSmartModSet` | `SmartModSet` raw value | `.smartModSet(_)` | Spotlight, menu bar |
| `userSmartModSet` | smart-set id | `.userSmartModSet(id:)` | Spotlight, Shortcuts, menu bar |
| `destination` | `problems` / `activity` / `restoreHistory` | `.problems` / `.activity` / `.restoreHistory` | menu bar |

Warnings and Errors are represented as built-in Smart Mod Sets (`warnings`,
`errors`), not as separate destinations, since that is how they route.

## Metadata

Each entity carries only safe, user-meaningful display metadata, generated from
current app state without duplicating business logic (it reuses the app's own
titles, symbols, and routes):

- `title`, optional `subtitle`
- `symbolName` (SF Symbol)
- `keywords` (safe search terms — author, version, folder name, etc.)
- `route`
- `surfaces` — which integrations expose it (`spotlight`, `shortcuts`, `menuBar`)

## Excluded for privacy

Never included as entity data: absolute/private paths, security-scoped
bookmarks, mod contents, config contents, logs, or diagnostics. Mutating actions
reached through any surface still route through the app's existing confirmation
and permission checks.

## Consumers

- **Spotlight** (`SeedBoxSpotlightIndexer`) indexes entities on the `spotlight`
  surface and renders them via `SeedBoxSpotlightIndex`.
- **App Shortcuts** select Mod Sets via the same identities.
- The menu bar, Finder services, and notification routing build on this model as
  those features land.
