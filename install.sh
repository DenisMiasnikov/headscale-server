#!/usr/bin/env bash

set -euo pipefail

# Default values
DEFAULT_DOCKER_USERNAME="DenisMiasnikov"
DEFAULT_UI_USERNAME="admin"
INSTALL_DIR="${HOME}/headscale"
REPO_URL="https://github.com/DenisMiasnikov/headscale-server.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if running in interactive mode
INTERACTIVE=true
BUILD_LOCAL=false
UNINSTALL=false
SKIP_DOCKER_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive)
            INTERACTIVE=false
            shift
            ;;
        --build-local)
            BUILD_LOCAL=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --skip-docker-install)
            SKIP_DOCKER_INSTALL=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --non-interactive    Run without prompts (reads env vars or uses defaults)"
            echo "  --build-local       Build Docker images locally instead of pulling from Docker Hub"
            echo "  --uninstall         Uninstall the stack (stops containers, removes files with confirmation)"
            echo "  --skip-docker-install  Skip Docker installation check"
            echo "  --help              Show this help message"
            echo ""
            echo "Environment variables (for --non-interactive mode):"
            echo "  DOMAIN, LETSENCRYPT_EMAIL, DOCKER_USERNAME, UI_USERNAME, UI_PASSWORD"
            echo "  SERVER_URL, BASE_DOMAIN, DEFAULT_USER, SESSION_SECRET, COOKIE_SECURE"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Prompt function for interactive mode
prompt() {
    local prompt_msg="$1"
    local default="$2"
    local var_name="$3"
    local input

    if [ "$INTERACTIVE" = true ]; then
        if [ -n "$default" ]; then
            read -r -p "$prompt_msg [$default]: " input </dev/tty
            if [ -n "$input" ]; then
                printf -v "$var_name" "%s" "$input"
            else
                printf -v "$var_name" "%s" "$default"
            fi
        else
            read -r -p "$prompt_msg: " input </dev/tty
            printf -v "$var_name" "%s" "$input"
        fi
    else
        # Non-interactive: use env var or default
        if [ -n "${!var_name:-}" ]; then
            printf -v "$var_name" "%s" "${!var_name}"
        elif [ -n "$default" ]; then
            printf -v "$var_name" "%s" "$default"
        else
            log_error "Non-interactive mode requires $var_name environment variable"
            exit 1
        fi
    fi
}

prompt_hidden() {
    local prompt_msg="$1"
    local var_name="$2"
    local input

    if [ "$INTERACTIVE" = true ]; then
        read -r -s -p "$prompt_msg: " input </dev/tty
        echo
        printf -v "$var_name" "%s" "$input"
    else
        if [ -z "${!var_name:-}" ]; then
            log_error "Non-interactive mode requires $var_name environment variable"
            exit 1
        fi
        printf -v "$var_name" "%s" "${!var_name}"
    fi
}

# Validate domain format
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)+$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

# Check if running on Linux
if [[ "$(uname)" != "Linux" ]]; then
    log_error "This script is designed for Linux VPS only."
    exit 1
fi

# Uninstall mode
if [ "$UNINSTALL" = true ]; then
    log_info "Uninstalling headscale-server from $INSTALL_DIR..."
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log_warn "Installation directory not found: $INSTALL_DIR"
        exit 0
    fi

    read -p "This will stop containers and remove all files. Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi

    read -p "Delete persistent data (headscale/data, acme.json)? This cannot be undone! (yes/no): " delete_data
    cd "$INSTALL_DIR" 2>/dev/null || true
    docker compose down 2>/dev/null || true

    if [[ "$delete_data" == "yes" ]]; then
        rm -rf headscale/data acme.json
        log_info "Deleted persistent data."
    fi

    # Remove all files except .git if it exists (user might want to keep repo)
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
    log_info "Uninstall complete. Directory: $INSTALL_DIR"
    exit 0
fi

# Check if installation already exists
if [ -d "$INSTALL_DIR" ]; then
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        log_warn "Existing installation found in $INSTALL_DIR"
        if [ "$INTERACTIVE" = true ]; then
            read -p "Overwrite? This will keep existing data but replace configuration files. (yes/no): " overwrite
            if [[ "$overwrite" != "yes" ]]; then
                log_info "Installation cancelled."
                exit 0
            fi
        else
            log_warn "Non-interactive mode: will use existing installation. Set a different INSTALL_DIR if needed."
        fi
    fi
fi

# Create install directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 1: Ensure Docker is installed
if [ "$SKIP_DOCKER_INSTALL" = false ]; then
    if ! command -v docker &> /dev/null; then
        log_info "Docker not found. Installing Docker..."
        
        # Check if we have sudo or are root
        if [[ $EUID -eq 0 ]]; then
            curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            sh /tmp/get-docker.sh
        elif command -v sudo &> /dev/null; then
            curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            sudo sh /tmp/get-docker.sh
        else
            log_error "Neither root nor sudo available. Please install Docker manually."
            exit 1
        fi

        # Start Docker service
        if command -v systemctl &> /dev/null; then
            if [[ $EUID -eq 0 ]]; then
                systemctl start docker
                systemctl enable docker
            else
                sudo systemctl start docker
                sudo systemctl enable docker
            fi
        fi

        log_info "Docker installed successfully."
    else
        log_info "Docker is already installed."
    fi
fi

# Ensure docker-compose is available (Docker Desktop includes it, but on Linux we might need separate plugin)
if ! docker compose version &> /dev/null; then
    log_warn "docker compose plugin not found. Installing..."
    if [[ $EUID -eq 0 ]]; then
        apt-get update && apt-get install -y docker-compose-plugin || true
        # Fallback: use separate docker-compose binary
        if ! docker compose version &> /dev/null; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
    else
        sudo apt-get update && sudo apt-get install -y docker-compose-plugin || true
        if ! docker compose version &> /dev/null; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o "${HOME}/.local/bin/docker-compose"
            chmod +x "${HOME}/.local/bin/docker-compose"
            # Add to PATH if needed
            export PATH="${HOME}/.local/bin:$PATH"
        fi
    fi
    log_info "docker-compose installed."
fi

# Step 2: Get repository files if not already present
if [ ! -f "docker-compose.yml" ]; then
    log_info "Downloading repository files..."
    if command -v git &> /dev/null; then
        git init
        git remote add origin "$REPO_URL" || true
        git fetch --depth=1 origin main || git fetch origin main
        git checkout -f main
    else
        # Download as zip
        log_info "Git not found. Downloading repository as zip..."
        if command -v wget &> /dev/null; then
            wget -q "https://github.com/lykabala/headscale-server/archive/refs/heads/main.zip" -O repo.zip
        elif command -v curl &> /dev/null; then
            curl -sL "https://github.com/lykabala/headscale-server/archive/refs/heads/main.zip" -o repo.zip
        else
            log_error "Neither git, wget, nor curl found. Please install one and retry."
            exit 1
        fi
        unzip -q repo.zip
        mv headscale-server-*/* .
        rm -rf headscale-server-* repo.zip
    fi
    log_info "Repository files ready."
fi

# Step 3: Gather configuration
log_info "Please provide the following configuration values."

# Domain
while true; do
    prompt "Enter your domain (e.g., homelab.example.com)" "" DOMAIN
    if [ -z "${DOMAIN:-}" ]; then
        log_warn "Domain is required."
    elif validate_domain "$DOMAIN"; then
        break
    fi
done

# Email
prompt "Enter your email for Let's Encrypt" "" LETSENCRYPT_EMAIL

# Docker Hub username
DEFAULT_DOCKER_USERNAME="${DEFAULT_DOCKER_USERNAME}"
prompt "Enter Docker Hub username" "$DEFAULT_DOCKER_USERNAME" DOCKER_USERNAME

# UI admin username
prompt "Enter UI admin username" "$DEFAULT_UI_USERNAME" UI_USERNAME

# UI admin password (hidden input)
if [ "$INTERACTIVE" = true ]; then
    prompt_hidden "Enter UI admin password (press Enter for random)" UI_PASSWORD
fi
if [ -z "${UI_PASSWORD:-}" ]; then
    UI_PASSWORD=$(openssl rand -hex 16)
    log_info "Generated random password: $UI_PASSWORD"
fi

# Derive other values
SERVER_URL="https://${DOMAIN}"
BASE_DOMAIN="tail.${DOMAIN}"
DEFAULT_USER="${DEFAULT_USER:-default}"
SESSION_SECRET="${SESSION_SECRET:-$(openssl rand -hex 32)}"
if [ "$DOMAIN" = "localhost" ] || [ "$DOMAIN" = "127.0.0.1" ]; then
    COOKIE_SECURE="false"
else
    COOKIE_SECURE="true"
fi

# Step 4: Write .env file
log_info "Creating .env file..."
cat > .env <<EOF
# Docker configuration
DOCKER_USERNAME=${DOCKER_USERNAME}

# Headscale configuration
DOMAIN=${DOMAIN}
SERVER_URL=${SERVER_URL}
BASE_DOMAIN=${BASE_DOMAIN}
DEFAULT_USER=${DEFAULT_USER}
UI_USERNAME=${UI_USERNAME}
UI_PASSWORD=${UI_PASSWORD}
SESSION_SECRET=${SESSION_SECRET}
COOKIE_SECURE=${COOKIE_SECURE}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
EOF

# Step 5: Create acme.json for Traefik
if [ ! -f "acme.json" ]; then
    log_info "Creating acme.json for Traefik certificates..."
    touch acme.json
    chmod 600 acme.json
fi

# Step 6: Pull or build images
log_info "Pulling/pre-building Docker images..."

if [ "$BUILD_LOCAL" = true ]; then
    log_info "Building images locally (this may take several minutes)..."
    # Build headscale image
    (cd headscale && docker build -t "${DOCKER_USERNAME}/headscale:latest" .)
    # Build UI image
    if [ -d "ui" ]; then
        (cd ui && docker build -t "${DOCKER_USERNAME}/headscale-ui:latest" .)
    else
        log_warn "UI source not found in 'ui/' directory. Will pull from Docker Hub instead."
        BUILD_LOCAL=false
    fi
else
    log_info "Pulling pre-built images from Docker Hub..."
    docker compose pull
fi

# Step 7: Start services
log_info "Starting services with docker compose..."
docker compose up -d

# Step 8: Wait for services to be healthy
log_info "Waiting for services to start..."
sleep 10

if docker compose ps | grep -q "unhealthy"; then
    log_warn "Some containers are unhealthy. Check logs: docker compose logs -f"
fi

# Success message
echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "Your Headscale instance is running at:"
echo "  🌐 UI:  ${SERVER_URL}"
echo "  🔧 API: ${SERVER_URL}/api/v1 (via Traefik)"
echo ""
echo "Login credentials:"
echo "  👤 Username: ${UI_USERNAME}"
echo "  🔑 Password: ${UI_PASSWORD}"
echo ""
echo "Useful commands:"
echo "  docker compose logs -f          # View logs"
echo "  docker compose restart <svc>   # Restart a service"
echo "  docker compose down            # Stop all services"
echo "  docker compose pull && docker compose up -d  # Update images"
echo ""
log_info "Make sure your domain's DNS points to this server's IP address."
echo ""
