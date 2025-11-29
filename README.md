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

Docker images are built using Nix flakes for reproducible builds:

```bash
nix build .#dockerImage
```

The resulting image is loaded into Docker via `docker load < result`.

### Development Tasks

- `npm run build` - Build all packages
- `npm run test` - Run all tests
- `npm run lint` - Lint all packages
- `npm run dev` - Start development servers
- `npm run serve` - Serve built packages
