# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deep Heating is a Home Assistant add-on that combines TRVs (Thermostatic Radiator Valves) with external temperature sensors for more efficient home heating. The web interface allows controlling target temperatures per room with scheduling.

## Commands

```bash
# Build and test (from packages/deep_heating/)
gleam build            # Build the Gleam package
gleam test             # Run all Gleam tests
gleam format           # Format Gleam code

# Docker image (via Nix)
nix build .#dockerImage              # Build Docker image
```

## Running Locally

```bash
cd packages/deep_heating
gleam run              # Start the server
```

Environment variables:
- `SUPERVISOR_URL` / `SUPERVISOR_TOKEN` - Home Assistant connection
- `HOME_CONFIG_PATH` - path to room/TRV configuration
- `LOG_LEVEL` - logging level (debug, info, warning, error)
- `DRY_RUN` - set to `true` to enable dry-run mode (logs commands instead of sending to HA)

## Architecture (packages/deep_heating)

The Gleam implementation follows a **Ports and Adapters** (Hexagonal) architecture with an OTP actor model.

### Architectural Philosophy

**Ports** = Message types and Subjects expressed in domain language
- Message types describe domain concepts (e.g., `RoomStateChanged`, `HouseModeChanged`, `AdjustmentChanged`)
- Subjects (`Subject(Message)`) provide the interface contracts between components

**Adapters** = Actors that receive and act upon those messages
- Actors implement the behaviour behind the ports
- Infrastructure concerns (HTTP, WebSocket, file I/O, HA API) live in adapters
- Domain logic should be testable without infrastructure

### Directory Structure (Vertical Slices)

The codebase is organized into vertical slices grouped by capability. Slices don't import each other's actors, only each other's types. The supervisor does the wiring via Subject injection.

```
packages/deep_heating/src/deep_heating/
├── rooms/                    # Room management slice
│   ├── room_actor.gleam      # Domain: aggregates room state
│   ├── room_decision_actor.gleam # Domain: computes TRV setpoints
│   ├── trv_actor.gleam       # Domain: holds TRV state
│   ├── trv_command_adapter_actor.gleam # Adapter: domain TrvCommand → HA
│   ├── rooms_supervisor.gleam # Per-room supervision factory
│   └── room_adjustments.gleam # Room temp adjustment persistence
│
├── home_assistant/           # HA integration slice (infrastructure)
│   ├── client.gleam          # HTTP client for HA API
│   ├── ha_poller_actor.gleam # Polls HA API for state
│   └── ha_command_actor.gleam # Sends commands to HA API
│
├── house_mode/               # House mode slice
│   └── house_mode_actor.gleam # Manages house-wide mode (Auto/Sleeping)
│
├── heating/                  # Heating control slice
│   ├── heating_control_actor.gleam # Domain: controls main boiler based on room demand
│   ├── boiler_command_adapter_actor.gleam # Adapter: domain BoilerCommand → HA
│   └── heating_control_adapter_actor.gleam # Adapter: receives HeatingControl commands
│
├── state/                    # UI state slice
│   └── state_aggregator_actor.gleam # Broadcasts state to UI clients
│
├── config/                   # Configuration slice
│   └── home_config.gleam     # Parses room/TRV configuration
│
├── scheduling/               # Scheduling slice
│   └── schedule.gleam        # Schedule types and logic
│
├── ui/                       # Lustre UI components
│   ├── app.gleam, view.gleam, update.gleam, model.gleam, msg.gleam
│   └── components/           # Room cards, controls, badges
│
# Root level (orchestration & shared types):
├── event_router_actor.gleam  # Routes HA events to correct handlers
├── supervisor.gleam          # OTP supervision tree
├── server.gleam              # WebSocket server infrastructure
├── mode.gleam                # Shared: HouseMode, RoomMode, HvacMode
├── state.gleam               # Shared: RoomState, DeepHeatingState
├── temperature.gleam         # Shared: Temperature type
└── entity_id.gleam           # Shared: ClimateEntityId, SensorEntityId
```

### Slice Boundaries

| Slice | Actors | Responsibility |
|-------|--------|----------------|
| **rooms/** | `room_actor`, `room_decision_actor`, `trv_actor`, `trv_command_adapter_actor` | Room temperature management, TRV control |
| **home_assistant/** | `ha_poller_actor`, `ha_command_actor` | HA API integration (infrastructure) |
| **house_mode/** | `house_mode_actor` | House-wide mode management |
| **heating/** | `heating_control_actor`, `boiler_command_adapter_actor`, `heating_control_adapter_actor` | Main boiler control |
| **state/** | `state_aggregator_actor` | UI state broadcasting |
| **config/** | - | Configuration parsing |
| **scheduling/** | - | Schedule types and evaluation |

**Shared types** (root level): `mode.gleam`, `state.gleam`, `temperature.gleam`, `entity_id.gleam` - used across multiple slices.

### Message Flow

```
Home Assistant API
        ↓
   HaPollerActor (infrastructure)
        ↓
   PollerEvent
        ↓
   EventRouterActor
        ├→ TrvActor → RoomActor → RoomDecisionActor → TrvCommandAdapterActor → HaCommandActor → HA API
        ├→ HeatingControlActor → BoilerCommandAdapterActor → HaCommandActor → HA API
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

1. **Respect slice boundaries**
   - Slices don't import each other's actors, only types
   - Add new actors to the appropriate existing slice
   - Create a new slice only for genuinely new capabilities

2. **Shared types live at root level**
   - Types used by multiple slices go in `mode.gleam`, `state.gleam`, etc.
   - Slice-specific types stay within the slice

3. **Message types live with their actors** (acceptable compromise)
   - Each actor defines its own `Message` type
   - Cross-actor communication uses explicit `Subject(OtherActor.Message)`

4. **Domain actors should be testable without infrastructure**
   - Inject time providers (`GetDateTime` function type)
   - Inject Subjects for dependencies rather than hardcoding
   - Use `skip_http` flags or similar for infrastructure actors

5. **Infrastructure adapters isolate external systems**
   - The `home_assistant/` slice handles all HA API concerns
   - Should be swappable without changing domain logic
   - Use testability hooks (spy subjects, skip flags)

6. **Pure functions for complex domain logic**
   - Extract into standalone functions (e.g., `compute_target_temperature`)
   - Can be tested independently of actors

7. **Subject ownership and OTP patterns**
   - See `docs/gleam-actor-architecture.md` for critical patterns around Subject ownership, `actor.named()`, and adapter actors
   - TL;DR: A Subject can only be received by the process that created it

## Testing

- Use `gleam test` from within `packages/deep_heating/`
- Tests use gleeunit framework

## Tooling

- **Nix**: Provides Gleam toolchain via `nix develop`
- **Pre-commit**: Hooks for code quality

## Branch Info

- The main branch is protected; changes must be made via a pull request

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
