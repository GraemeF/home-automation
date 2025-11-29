# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deep Heating is a Home Assistant add-on that combines TRVs (Thermostatic Radiator Valves) with external temperature sensors for more efficient home heating. The web interface allows controlling target temperatures per room with scheduling.

## Commands

```bash
# Development
bun run build          # Build all packages (uses turbo)
bun run test           # Run all tests
bun run lint           # Lint all packages
bun run dev            # Start dev servers (socketio + web)
bun run format         # Format code with Prettier

# Single package testing
bun test --filter deep-heating-rx
bun test --filter deep-heating-rx -- --testNamePattern="pattern"

# Docker image (via Nix)
nix build .#dockerImage              # Build Docker image
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

- `deep-heating-socketio` - Express + Socket.IO backend server
- `deep-heating-web` - SvelteKit frontend

**Deployment**:

- `deep-heating` - Combined Docker image (nginx + backend + frontend)

### Package Dependencies

```
deep-heating-web → deep-heating-types
deep-heating-socketio → deep-heating-types, deep-heating-rx, deep-heating-state
deep-heating-rx → deep-heating-types, deep-heating-home-assistant, rxx
deep-heating-state → deep-heating-types
deep-heating-home-assistant → deep-heating-types
```

### Key Patterns

- **Reactive streams**: RxJS throughout for state and event handling
- **Effect library**: Used for typed functional effects in some modules
- **Real-time**: Socket.IO for client-server communication
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
