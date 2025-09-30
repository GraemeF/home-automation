# Home Automation

This monorepo houses projects that can be used to automate your home.

[![Open your Home Assistant instance and show the add add-on repository dialog with this repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FGraemeF%2Fhome-automation)

## Add-ons

This repository contains the following add-ons:

### [Deep Heating](./packages/deep-heating/)

Combine TRVs with external temperature sensors to heat your home more efficiently.

## Development

This monorepo uses [Turborepo](https://turbo.build/repo) for task orchestration and caching.

### Building Docker Images

Build Docker images from the repository root using the following commands:

**Deep Heating (combined socketio + web)**:

```bash
docker build -f packages/deep-heating/Dockerfile -t deep-heating:latest .
```

**Deep Heating SocketIO (standalone)**:

```bash
docker build -f packages/deep-heating-socketio/Dockerfile -t deep-heating-socketio:latest .
```

**Deep Heating Web (standalone)**:

```bash
docker build -f packages/deep-heating-web/Dockerfile -t deep-heating-web:latest .
```

All Dockerfiles use `turbo prune` to create optimized multi-stage builds with proper caching layers.

#### Multi-platform builds

To build for multiple platforms (e.g., ARM64 for Raspberry Pi and AMD64):

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -f packages/deep-heating/Dockerfile \
  -t your-registry/deep-heating:latest \
  --push .
```

#### Using npm scripts

```bash
npm run docker:build:deep-heating      # Build combined image
npm run docker:build:socketio          # Build socketio standalone
npm run docker:build:web               # Build web standalone
npm run docker:build:all               # Build all images
```

### Development Tasks

- `npm run build` - Build all packages
- `npm run test` - Run all tests
- `npm run lint` - Lint all packages
- `npm run dev` - Start development servers
- `npm run serve` - Serve built packages
