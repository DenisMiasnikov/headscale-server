# Headscale Server Infrastructure

Self-hosted Headscale with automatic HTTPS using Traefik reverse proxy.

This repository contains **only the server infrastructure**. The UI is a separate repository (`lykabala-headscale-ui`) and is pulled as a Docker image.

---

## One-Command Install (Recommended for New Users)

On a fresh VPS (Ubuntu/Debian), simply run:

```bash
curl -sSL https://raw.githubusercontent.com/DenisMiasnikov/headscale-server/main/install.sh | bash
```

The script will:
- Install Docker if not present
- Prompt for your domain and email
- Generate secure secrets
- Configure and start all services

After installation, visit `https://your-domain` and log in with the credentials printed at the end.

**Optional flags:**
- `--build-local` – Build Docker images locally instead of pulling from Docker Hub (slower but no registry dependency)
- `--non-interactive` – Run without prompts (set environment variables beforehand)
- `--skip-docker-install` – Skip Docker installation check (if already installed)

Example with arguments:
```bash
curl -sSL https://raw.githubusercontent.com/yourusername/headscale-server/main/install.sh | bash -s -- --non-interactive --domain example.com --email admin@example.com
```

---

## Manual Setup (For Maintainers / Advanced Users)

If you prefer manual control or already have Docker:

1. Clone the repo:

   ```bash
   git clone <your-server-repo-url>
   cd headscale-server
   ```

2. Create `.env`:

   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your values:
   - `DOCKER_USERNAME` – your Docker Hub username
   - `DOMAIN` – your public domain (e.g., `homelab.example.com`)
   - `SERVER_URL` – typically `https://<DOMAIN>`
   - `BASE_DOMAIN` – MagicDNS base domain (`tail.<DOMAIN>`)
   - `DEFAULT_USER` – default namespace (e.g., `admin`)
   - `UI_USERNAME` / `UI_PASSWORD` – UI admin credentials
   - `SESSION_SECRET` – generate with `openssl rand -hex 32`
   - `LETSENCRYPT_EMAIL` – for SSL certificate
   - `COOKIE_SECURE` – `true` for HTTPS, `false` for HTTP

4. Pull and start services:

   ```bash
   docker compose pull
   docker compose up -d
   ```

5. Open the UI: `https://<your-domain>`

## Architecture

Services:

- **Traefik** – Reverse proxy and SSL automation (ports 80/443, Let's Encrypt)
- **Headscale** – Tailscale coordination server (internal port 8080)
- **UI** – Web interface (`yourname/headscale-ui:latest`)

Traefik automatically:
- Obtains and renews Let's Encrypt certificates
- Routes HTTP to HTTPS
- Directs traffic:
  - Headscale API paths (`/register`, `/key`, `/machine`, etc.) → `headscale:8080`
  - All other traffic → `ui:3000`

## Environment Variables

All configuration is in `.env`:

| Variable | Description | Required |
|----------|-------------|----------|
| `DOCKER_USERNAME` | Docker Hub username (for pulling images) | Yes |
| `DOMAIN` | Public domain (e.g., `homelab.example.com`) | Yes |
| `SERVER_URL` | Full server URL (`https://<DOMAIN>`) | Yes |
| `BASE_DOMAIN` | MagicDNS base domain (`tail.<DOMAIN>`) | Yes |
| `DEFAULT_USER` | Default namespace name | Yes |
| `UI_USERNAME` | UI login username | Yes |
| `UI_PASSWORD` | UI login password | Yes |
| `SESSION_SECRET` | Random secret for session cookies | Yes |
| `LETSENCRYPT_EMAIL` | Email for SSL certificate | Yes |
| `COOKIE_SECURE` | `true` for HTTPS, `false` for HTTP | Yes |

## Ports

- `80` – HTTP (redirects to HTTPS + ACME challenge)
- `443` – HTTPS (UI and Headscale API)

Headscale API (port 8080) is **not** exposed externally; only accessible through the Docker network.

## Operations

View logs:

```bash
docker compose logs -f
docker compose logs -f headscale
docker compose logs -f ui
docker compose logs -f traefik
```

Restart a service:

```bash
docker compose restart <service>
```

Stop all services:

```bash
docker compose down
```

## Local Development

For local testing without HTTPS:

1. Set `COOKIE_SECURE=false` in `.env`
2. Pull and start:

   ```bash
   docker compose pull
   docker compose up -d
   ```

3. Access at `http://localhost` (Traefik will still obtain a certificate if domain is real; for localhost you may need to set `DOMAIN=localhost` and use self-signed).

### Hot-Reload Development

To work on the UI code locally:

1. Clone the UI repository into this directory:

   ```bash
   git clone ../lykabala-headscale-ui ui
   ```

2. Edit `docker-compose.yml`: change `image:` to `build: ./ui` for the `ui` service.

3. Rebuild and start:

   ```bash
   docker compose up -d --build
   ```

4. After changes, push to the UI repo to trigger its own CI/CD.

## CI/CD

Pushing to `main`/`master` in this repository triggers:

- Build and push `headscale` Docker image to Docker Hub (`latest` and commit SHA tags)
- SSH into your VPS (secrets: `VPS_HOST`, `VPS_USERNAME`, `VPS_SSH_KEY`, `DEPLOY_PATH`)
- Pull latest images and restart services

The UI is deployed independently from its own repository.

## Directory Structure

```
headscale-server/
├── headscale/           # Headscale image config and persistent data
│   ├── config.yaml
│   ├── data/            # SQLite DB, API key (persisted)
│   ├── Dockerfile
│   └── entrypoint.sh
├── traefik.yml          # Traefik static configuration
├── acme.json            # Let's Encrypt certificates (created on first run)
├── docker-compose.yml   # Orchestration
├── .env.example         # Environment template
├── README.md
└── AGENTS.md            # Guidelines for AI agents
```

## Traefik Details

Traefik is configured via `traefik.yml`:

- **Entry Points**:
  - `web` (port 80) – redirects all traffic to HTTPS
  - `websecure` (port 443) – TLS termination with Let's Encrypt
- **Certificate Resolver**: `le` (Let's Encrypt) using HTTP challenge
- **Docker Provider**: Instantly discovers services with `traefik.enable=true` label
- **Network**: All services share `headscale-net` bridge

Routers and services are defined via **Docker labels** on the `headscale` and `ui` services:

- `headscale` – routes specific API paths to port 8080
- `ui` – routes all other traffic to port 3000

## Troubleshooting

**Certificate issues?**
- Ensure `acme.json` exists and has `600` permissions
- Check Traefik logs: `docker compose logs traefik`
- Verify `DOMAIN` resolves to your VPS and ports 80/443 are open
- Delete `acme.json` and restart to force reissue (if stuck)

**Containers not starting?**
```bash
docker compose ps
docker compose logs <service>
```

**UI can't connect to Headscale?**
- Check `docker compose ps headscale` is healthy
- Verify `HEADSCALE_URL` environment in UI container is `http://headscale:8080`
- Ensure both containers share `headscale-net` network

**Need to disable HTTPS temporarily?**
Set `COOKIE_SECURE=false` and change Traefik entrypoint to serve on both HTTP/HTTPS, or use a self-signed cert.

## License

[Your license here]
