# Home Automation

This monorepo houses projects that can be used to automate your home.

[![Open your Home Assistant instance and show the add add-on repository dialog with this repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FGraemeF%2Fhome-automation)

## Add-ons

This repository contains the following add-ons:

### [Deep Heating](./packages/deep_heating/)

Combine TRVs with external temperature sensors to heat your home more efficiently.

Built with [Gleam](https://gleam.run/) on the BEAM (Erlang runtime) using an actor-based architecture.

## Development

### Prerequisites

This project uses [Nix](https://nixos.org/) for reproducible development environments:

```bash
nix develop
```

This provides Gleam, Erlang/OTP, and all required tools.

### Development Tasks

```bash
cd packages/deep_heating
gleam build      # Build the project
gleam test       # Run tests
gleam run        # Run the project
```

### Building Docker Images

Docker images are built using Nix flakes for reproducible builds:

```bash
nix build .#dockerImage
```

The resulting image is loaded into Docker via `docker load < result`.

## Architecture

See the [architecture docs](./docs/) for details on the actor-based design.
