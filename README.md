# Headscale Server Infrastructure

Self-hosted Headscale server with Nginx reverse proxy and Let's Encrypt SSL.

This repository contains **only the server infrastructure**. The UI is a separate repository (`lykabala-headscale-ui`) and is pulled as a Docker image.

## Quick Start (VPS)

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
   - `DOMAIN` – your public domain
   - `SERVER_URL` – typically `https://<DOMAIN>`
   - `BASE_DOMAIN` – MagicDNS base (e.g. `tail.<DOMAIN>`)
   - `DEFAULT_USER` – default namespace name
   - `UI_USERNAME` / `UI_PASSWORD` – UI admin credentials
   - `SESSION_SECRET` – generate with `openssl rand -hex 32`
   - `LETSENCRYPT_EMAIL` – for SSL certificate
   - `COOKIE_SECURE` – `true` for HTTPS, `false` for local HTTP

4. Pull and start services:

   ```bash
   docker compose pull
   docker compose up -d
   ```

5. Open the UI: `https://<your-domain>`

## How It Works

- **Headscale**: Runs on port 8080 internally, manages the Tailscale network
- **UI**: Separate Docker image (`yourname/headscale-ui:latest`) served via Nginx
- **Nginx**: Reverse proxy on ports 80/443, handles SSL termination and routing
- **Certbot**: Automatically obtains and renews Let's Encrypt certificates

The `docker-compose.yml` uses prebuilt Docker images. On first run:
- Headscale generates its config from `headscale/config.template.yaml`
- Creates default namespace and API key
- Nginx starts with self-signed cert initially, then Certbot replaces it

## Environment Variables

All configuration is in `.env`:

| Variable | Description |
|----------|-------------|
| `DOCKER_USERNAME` | Docker Hub username (for pulling images) |
| `DOMAIN` | Public domain (e.g. `homelab.example.com`) |
| `SERVER_URL` | Full server URL (`https://<DOMAIN>`) |
| `BASE_DOMAIN` | MagicDNS base domain (`tail.<DOMAIN>`) |
| `DEFAULT_USER` | Default namespace (e.g. `admin`) |
| `UI_USERNAME` | UI login username |
| `UI_PASSWORD` | UI login password |
| `SESSION_SECRET` | Random secret for session cookies |
| `COOKIE_SECURE` | `true` for HTTPS, `false` for HTTP |
| `LETSENCRYPT_EMAIL` | Email for SSL certificate notifications |

## Ports

- `80` – HTTP (redirects to HTTPS + ACME challenge)
- `443` – HTTPS (UI and API)

Headscale API (port 8080) is **not** exposed externally; only accessible through the Docker network.

## Operations

View logs:

```bash
docker compose logs -f
docker compose logs -f headscale
docker compose logs -f nginx
docker compose logs -f certbot
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

3. Access at `http://localhost`

### Hot-Reload Development

If you want to modify the UI code locally:

1. Clone the UI repository into this directory:

   ```bash
   git clone ../lykabala-headscale-ui ui
   ```

2. Edit `docker-compose.yml`: change `image: ...` to `build: ./ui` for the `ui` service (and optionally `headscale` if you need to modify server config)

3. Rebuild and start:

   ```bash
   docker compose up -d --build
   ```

4. After changes, push to the UI repo to trigger its own CI/CD.

## CI/CD

This repository's GitHub Actions (`/.github/workflows/deploy.yml`):

- Triggers on push to `main`/`master`
- Builds the Headscale Docker image
- Pushes to Docker Hub with `latest` and commit SHA tags
- Connects to your VPS via SSH
- Pulls latest images and restarts services

The **UI repository** has its own CI/CD that builds and pushes `yourname/headscale-ui:latest`.

Both deployments are independent. Pushing to the server repo updates the infrastructure; pushing to the UI repo updates the frontend.

## Directory Structure

```
headscale-server/
├── headscale/
│   ├── config.template.yaml   # Headscale configuration template
│   ├── data/                  # Persistent data (SQLite, API key)
│   ├── Dockerfile             # Headscale image build
│   └── entrypoint.sh          # Entrypoint script
├── nginx/
│   ├── nginx.conf.template    # HTTPS reverse proxy config
│   ├── nginx.http.conf.template # HTTP redirect config
│   └── entrypoint.sh          # Generates configs and starts nginx
├── certbot/
│   └── entrypoint.sh          # Certbot automation script
├── .github/workflows/
│   └── deploy.yml             # CI/CD pipeline
├── docker-compose.yml         # Orchestration
├── .env.example               # Environment template
├── README.md
└── AGENTS.md                  # Guidelines for AI agents
```

## Troubleshooting

**Check container status:**
```bash
docker compose ps
```

**Inspect logs:**
```bash
docker compose logs -f <service>
```

**HTTPS not working?**
- Ensure DNS points to your VPS
- Ports 80 and 443 are open
- `.env` has correct `DOMAIN` and `LETSENCRYPT_EMAIL`
- The `certbot` container has written certificates to `certbot/conf/`

**UI not connecting to Headscale?**
- Verify `HEADSCALE_URL` in UI container logs
- Check that Headscale container is healthy (`docker compose ps headscale`)
- Ensure both containers are on the same Docker network (`headscale-net`)

## License

[Your license here]
