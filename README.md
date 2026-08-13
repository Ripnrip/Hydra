# BrainOracle

Context Hydration Engine — sources → enrich → vault → export. 100% Swift.

## What it does

Turns scattered sources (Claude plans, sessions, changelogs, git, ad-hoc files) into a connected, living second brain. Equally awesome for humans (SwiftUI) and agents (CLI, MCP).

```
Source → Scan → Classify → Enrich → Outbox → Project → Export
                       (tags, links,        (SQLite)    (Obsidian)   (pluggable)
                        color, authority)
```

### Hydration modes
- **Backfill** — historical batch scan
- **Watch** — real-time FS events
- **Ad-hoc** — interactive drag/paste
- **Query** — oracle: traverse the hydrated graph

## Modules

| Module | Purpose |
|--------|---------|
| `BrainCore` | Domain models, pipeline contracts, authority hierarchy, 8-state delivery model |
| `BrainVault` | Obsidian vault scanner, writer, inventory, PARA categories |
| `BrainHealth` | Health checks, FS watcher, maintenance scheduler (all Swift, no bash) |
| `BrainMCP` | JSON-RPC 2.0 MCP server (Claude stdio) |
| `BrainCLI` | `brain-oracle scan\|health\|hydrate\|search\|serve` |
| `BrainApp` | SwiftUI app (Hydrate / Vault / Oracle / Health tabs) |

## Stack

- Swift 6.2, strict concurrency
- macOS 15+
- SwiftUI + TCA 1.15+ for complex state
- Hummingbird 2.x for MCP server
- swift-argument-parser for CLI
- Pointfree SnapshotTesting

## Building

```bash
swift build
swift test
```

## Dogfooding

Tested against SecondBrain vault (331 notes, 685 tags, PARA structure, 16 Obsidian plugins).

## Canon

Swift implementation canon in `docs/canon/` (general + Andromeda patterns).

## License

Private.
