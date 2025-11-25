# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deep Heating is a Home Assistant add-on that combines TRVs (Thermostatic Radiator Valves) with external temperature sensors for more efficient home heating. The web interface allows controlling target temperatures per room with scheduling.

## Commands

```bash
# Development
npm run build          # Build all packages (uses turbo)
npm run test           # Run all tests
npm run lint           # Lint all packages
npm run dev            # Start dev servers (socketio + web)
npm run format         # Format code with Prettier

# Single package testing
npm test --workspace=packages/deep-heating-rx
npm test --workspace=packages/deep-heating-rx -- --testNamePattern="pattern"

# Docker builds
npm run docker:build:deep-heating   # Combined image
npm run docker:build:all            # All images
```

## Architecture

### Monorepo Structure

This is an npm workspaces monorepo orchestrated by Turborepo. Packages are in `packages/`:

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

- **Jest**: Library packages (`packages/deep-heating-*/`)
- **Vitest**: SvelteKit frontend (`packages/deep-heating-web/`)
- Tests run after lint and depend on building dependencies first (see turbo.json)

## Tooling

- **Node**: 20.19.5 (managed via mise in `.mise.toml`)
- **Package manager**: npm 10.9.4
- **Build orchestration**: Turborepo with caching
- **Pre-commit**: Husky runs Prettier on staged files
