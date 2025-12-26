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

### Key Patterns

- **Reactive streams**: RxJS throughout for state and event handling
- **Effect library**: Used for typed functional effects in some modules
- **Real-time**: Native WebSocket for client-server communication
- **Strict TypeScript**: `exactOptionalPropertyTypes: true` enabled

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
bd sync                               # Sync with remote (run at session end)
```

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
