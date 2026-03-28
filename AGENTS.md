# AGENTS.md

This file provides guidance for agentic coding agents operating in this repository.
It describes how to build, run, extend, and maintain the Headscale + UI stack.

---

# Project Overview

This repository contains a self-hosted Headscale server infrastructure:

- Headscale (SQLite backend)
- Nginx reverse proxy with Let's Encrypt
- Docker Compose orchestration
- CI/CD with automatic deployment

This repository manages **only the server infrastructure**. The UI is a separate repository (`lykabala-headscale-ui`) that is pulled as a Docker image.

Main directories:

- `docker-compose.yml` – service orchestration (includes UI as external image)
- `headscale/` – Headscale configuration and persistent data
- `nginx/` – Reverse proxy configuration
- `certbot/` – SSL certificate automation

---

# Build & Run Commands

## Setup (First Time)

1. Clone this repository to your VPS or local machine.

2. Create `.env` from the template:

   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your values:
   - Set `DOCKER_USERNAME` (your Docker Hub username)
   - Set `DOMAIN`, `SERVER_URL`, `BASE_DOMAIN`
   - Set admin credentials (`UI_USERNAME`, `UI_PASSWORD`)
   - Generate a strong `SESSION_SECRET` (e.g., `openssl rand -hex 32`)
   - Set `LETSENCRYPT_EMAIL`

4. Pull and start all services:

   ```bash
   docker compose pull
   docker compose up -d
   ```

## Operations

View logs:

```bash
docker compose logs -f
docker compose logs -f headscale
docker compose logs -f ui
docker compose logs -f nginx
docker compose logs -f certbot
```

Stop services:

```bash
docker compose down
```

Restart a service:

```bash
docker compose restart <service-name>
```

## Development (Local with hot-reload)

For active UI development, you may want to clone the UI repository into a subfolder and switch `docker-compose.yml` to use `build: ./ui` temporarily. The default configuration uses prebuilt images for consistency.

1. Clone UI repo alongside this repo:
   ```bash
   cd /path/to/headscale-server
   git clone ../lykabala-headscale-ui ui
   ```

2. Edit `docker-compose.yml`:
   - Change `image: ...` to `build: ./ui` for both `headscale` and `ui` services if you want local builds.
   - Note: The `headscale` service can still be built from `./headscale` locally.

3. Rebuild and start:
   ```bash
   docker compose up -d --build
   ```

For production deployments, use the prebuilt images (the `image:` directives in the repo).

## CI/CD

- Pushing to `main`/`master` triggers GitHub Actions:
  - Builds `headscale` Docker image
  - Pushes to Docker Hub with `latest` and commit SHA tags
  - SSHes to your VPS (secrets `VPS_HOST`, `VPS_USERNAME`, `VPS_SSH_KEY`, `DEPLOY_PATH`)
  - Pulls images and restarts services

The UI is built and deployed from its own repository independently.
