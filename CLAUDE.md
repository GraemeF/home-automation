# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deep Heating is a Home Assistant add-on that combines TRVs (Thermostatic Radiator Valves) with external temperature sensors for more efficient home heating. The web interface allows controlling target temperatures per room with scheduling.

## Commands

```bash
# Development
turbo build            # Build all packages
turbo test             # Run all tests
turbo lint             # Lint all packages
bun run format         # Format code with Prettier

# Single package testing
bun test --filter deep-heating-rx
bun test --filter deep-heating-rx -- --testNamePattern="pattern"

# Docker image (via Nix)
nix build .#dockerImage              # Build Docker image
```

## Running Locally

To run the full stack locally (frontend + backend):

```bash
turbo serve
```

This starts:

- **Frontend**: http://localhost:5173/ (SvelteKit dev server)
- **Backend**: WebSocket server on port 8085

Environment variables are loaded from `.env.local`:

- `API_URL` - tells the frontend where to find the backend WebSocket
- `SUPERVISOR_URL` / `SUPERVISOR_TOKEN` - Home Assistant connection
- `HOME_CONFIG_PATH` - path to room/TRV configuration

To run just the backend (useful for debugging server-side issues):

```bash
turbo serve --filter deep-heating-server
```

## Architecture

### Monorepo Structure

This is a Bun workspaces monorepo orchestrated by Turborepo. Packages are in `packages/`:

**Libraries** (build to `dist/`, use `@home-automation/` scope):

- `deep-heating-types` - Core TypeScript interfaces and types
- `deep-heating-home-assistant` - Home Assistant WebSocket API client
- `deep-heating-rx` - RxJS reactive streams for heating logic
- `deep-heating-state` - State management
- `rxx` - General RxJS utilities
- `dictionary` - Shared constants/terminology

**Applications**:

- `deep-heating-server` - WebSocket backend server (Effect + Bun)
- `deep-heating-web` - SvelteKit frontend

**Deployment**:

- `deep-heating` - Combined Docker image (nginx + backend + frontend)

### Package Dependencies

```
deep-heating-web → deep-heating-types
deep-heating-server → deep-heating-types, deep-heating-rx, deep-heating-state
deep-heating-rx → deep-heating-types, deep-heating-home-assistant, rxx
deep-heating-state → deep-heating-types
deep-heating-home-assistant → deep-heating-types
```

### Key Patterns (TypeScript)

- **Reactive streams**: RxJS throughout for state and event handling
- **Effect library**: Used for typed functional effects in some modules
- **Real-time**: Native WebSocket for client-server communication
- **Strict TypeScript**: `exactOptionalPropertyTypes: true` enabled

## Gleam Architecture (packages/deep_heating)

The Gleam implementation follows a **Ports and Adapters** (Hexagonal) architecture with an OTP actor model.

### Architectural Philosophy

**Ports** = Message types and Subjects expressed in domain language
- Message types describe domain concepts (e.g., `RoomStateChanged`, `HouseModeChanged`, `AdjustmentChanged`)
- Subjects (`Subject(Message)`) provide the interface contracts between components

**Adapters** = Actors that receive and act upon those messages
- Actors implement the behaviour behind the ports
- Infrastructure concerns (HTTP, WebSocket, file I/O, HA API) live in adapters
- Domain logic should be testable without infrastructure

### Directory Structure

```
packages/deep_heating/src/deep_heating/
├── actor/                    # Actor implementations (adapters)
│   ├── event_router_actor    # Routes HA events to correct handlers
│   ├── ha_command_actor      # Infrastructure: sends commands to HA API
│   ├── ha_poller_actor       # Infrastructure: polls HA API for state
│   ├── heating_control_actor # Controls main heating system
│   ├── house_mode_actor      # Domain: manages house-wide mode
│   ├── room_actor            # Domain: aggregates room state
│   ├── room_decision_actor   # Domain: computes TRV setpoints
│   ├── state_aggregator_actor # Broadcasts state to UI clients
│   └── trv_actor             # Domain: holds TRV state
├── mode.gleam               # Domain types: HouseMode, RoomMode, HvacMode
├── schedule.gleam           # Domain logic: schedules, time handling
├── state.gleam              # Domain types: RoomState, DeepHeatingState
├── temperature.gleam        # Domain type: Temperature with constraints
├── entity_id.gleam          # Domain type: ClimateEntityId
├── home_assistant.gleam     # Infrastructure: HA HTTP client
├── server.gleam             # Infrastructure: WebSocket server
├── supervisor.gleam         # OTP supervision tree
└── rooms_supervisor.gleam   # Per-room supervision factory
```

### Layer Separation

| Layer | Files | Responsibility |
|-------|-------|----------------|
| **Domain Types** | `mode.gleam`, `state.gleam`, `temperature.gleam`, `schedule.gleam`, `entity_id.gleam` | Pure data types, no I/O |
| **Domain Logic** | `room_actor`, `room_decision_actor`, `house_mode_actor`, `trv_actor` | Business rules, testable with mocked time |
| **Infrastructure** | `home_assistant.gleam`, `ha_poller_actor`, `ha_command_actor`, `server.gleam` | HTTP, WebSocket, polling |
| **Orchestration** | `supervisor.gleam`, `rooms_supervisor.gleam` | Process supervision |

### Message Flow

```
Home Assistant API
        ↓
   HaPollerActor (infrastructure)
        ↓
   PollerEvent
        ↓
   EventRouterActor
        ├→ TrvActor → RoomActor → RoomDecisionActor → HaCommandActor → HA API
        └→ HouseModeActor → broadcasts to RoomActors
```

### Domain vs Infrastructure Examples

**Domain Actor** (`room_decision_actor.gleam`):
```gleam
/// Pure domain function - no infrastructure dependencies
fn compute_desired_trv_target(
  room_target: Temperature,
  room_temp: Option(Temperature),
  trv_temp: Option(Temperature),
) -> Temperature {
  // Offset compensation: trvTarget = roomTarget + trvTemp - roomTemp
  // Clamped to safe bounds (7-32°C)
}
```

**Infrastructure Adapter** (`ha_command_actor.gleam`):
```gleam
/// Sends HTTP requests to Home Assistant
/// Debounces commands (5s) to avoid API flooding
/// Has skip_http flag for testing
```

### Development Guidelines

When adding new features to the Gleam codebase:

1. **Define domain types first** in dedicated files (`mode.gleam`, `state.gleam`, etc.)
   - Types should express domain concepts, not implementation details
   - No infrastructure imports in domain type files

2. **Message types live with their actors** (acceptable compromise)
   - Each actor defines its own `Message` type
   - Cross-actor communication uses explicit `Subject(OtherActor.Message)`

3. **Domain actors should be testable without infrastructure**
   - Inject time providers (`GetDateTime` function type)
   - Inject Subjects for dependencies rather than hardcoding
   - Use `skip_http` flags or similar for infrastructure actors

4. **Infrastructure adapters isolate external systems**
   - HTTP clients, WebSocket handlers, file I/O
   - Should be swappable without changing domain logic
   - Use testability hooks (spy subjects, skip flags)

5. **Pure functions for complex domain logic**
   - Extract into standalone functions (e.g., `compute_target_temperature`)
   - Can be tested independently of actors

## Testing

- **Bun native test runner**: All packages use `bun test`
- Tests run after lint and depend on building dependencies first (see turbo.json)

## Tooling

- **Package manager**: Bun (provided via `nix develop` from flake.nix)
- **Build orchestration**: Turborepo with caching
- **Pre-commit**: Husky runs Prettier on staged files

## Changesets

`bun run changeset` is interactive and won't work for Claude. To add a changeset manually, create a markdown file in `.changeset/` (e.g., `fix-temperature-rounding.md`):

```markdown
---
'@home-automation/deep-heating-rx': patch
---

Brief description of what changed
```

The frontmatter lists affected packages and bump type (`patch`, `minor`, `major`). Changes to libraries automatically bump `@home-automation/deep-heating` via dependencies.

- The main branch is protected; changes must be made via a pull request.

## Issue Tracking with Beads

This repo uses [beads](https://github.com/steveyegge/beads) for issue tracking.

```bash
bd ready                              # Show issues ready to work on
bd list --status=open                 # All open issues
bd show <id>                          # View issue details
bd create --title="..." --type=task   # Create issue (type: task|bug|feature)
bd update <id> --status=in_progress   # Claim work
bd close <id>                         # Mark complete
bd sync                               # Sync with remote (at session end, from repo root!)
```

**Important:** Always run `bd sync` from the repository root, not from a subdirectory. The command needs access to the git worktree metadata.

Issues sync to the `beads-metadata` branch automatically via daemon. The database is shared across all worktrees.

## Git Worktree Workflow

**All work happens in worktrees. Nothing is done directly on main.**

### Repository Structure

```
home-automation/
├── main/              # Main branch worktree (primary checkout)
├── feature-foo/       # Feature branch worktree
└── fix-bar/           # Fix branch worktree
```

### Creating a New Worktree

```bash
cd home-automation/main
git fetch origin
git worktree add ../feature-name -b feature/descriptive-name
cd ../feature-name
```

### Cleaning Up After PR Merge

```bash
cd home-automation/main
git worktree remove ../feature-name
git branch -d feature/descriptive-name
```

### Useful Commands

```bash
git worktree list     # See all active worktrees
git worktree prune    # Clean up stale references
```
