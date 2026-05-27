#!/bin/bash
# ============================================================
#  Nextcloud + Collabora Online + forms — Interactive Installer
#  Author : Amin Shahamiri
#  Repo   : https://github.com/Amin-Shahamiri/nextcloud-collabora-stack
# ============================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ──────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $1${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }

confirm() {
    read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" ans
    [[ "${ans,,}" == "y" ]]
}

# ── Banner ───────────────────────────────────────────────────
clear
echo -e "${CYAN}"
cat << 'BANNER'
  _   _           _       _                    _
 | \ | | _____  _| |_ ___| | ___  _   _  __| |
 |  \| |/ _ \ \/ / __/ __| |/ _ \| | | |/ _` |
 | |\  |  __/>  <| || (__| | (_) | |_| | (_| |
 |_| \_|\___/_/\_\\__\___|_|\___/ \__,_|\__,_|

  + Collabora Online + forms Installer
BANNER
echo -e "${NC}"
echo -e "${BOLD}  A production-ready, self-hosted Google Drive & Google Docs alternative powered by Nextcloud and Collabora Online.${NC}"
echo -e "  ${CYAN}github.com/Amin-Shahamiri/nextcloud-collabora-stack${NC}\n"

# ── Preflight checks ─────────────────────────────────────────
header "Step 1 — Preflight checks"

command -v docker  &>/dev/null || error "Docker is not installed. Please install Docker first."
command -v curl    &>/dev/null || error "curl is not installed. Run: sudo dnf install -y curl"

success "Docker found: $(docker --version | cut -d' ' -f3 | tr -d ',')"
success "Docker Compose found: $(docker compose version | cut -d' ' -f4)"

if [[ $EUID -eq 0 ]]; then
    warn "Running as root. It's safer to run as a regular user with sudo access."
    confirm "Continue anyway?" || exit 0
fi

# ── Swap ─────────────────────────────────────────────────────
header "Step 2 — Swap memory"

if swapon --show | grep -q .; then
    success "Swap already exists: $(swapon --show --noheadings | awk '{print $3}' | head -1)"
else
    info "No swap detected. Creating 2G swapfile at /swapfile..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    sysctl vm.swappiness=10
    grep -q 'vm.swappiness' /etc/sysctl.conf \
        && sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf \
        || echo 'vm.swappiness=10' >> /etc/sysctl.conf
    success "2G swap created and enabled (persists across reboots)"
fi

# ── User input ───────────────────────────────────────────────
header "Step 3 — Configuration"

# Nextcloud domain
while true; do
    read -rp "$(echo -e "${CYAN}Nextcloud domain${NC} (e.g. cloud.example.com): ")" NEXTCLOUD_DOMAIN
    [[ -n "$NEXTCLOUD_DOMAIN" ]] && break
    warn "Domain cannot be empty."
done

# Collabora domain
while true; do
    read -rp "$(echo -e "${CYAN}Collabora domain${NC} (e.g. office.example.com): ")" COLLABORA_DOMAIN
    [[ -n "$COLLABORA_DOMAIN" ]] && break
    warn "Domain cannot be empty."
done

# Email for Let's Encrypt
while true; do
    read -rp "$(echo -e "${CYAN}Email for SSL certificates${NC} (Let's Encrypt): ")" CERTBOT_EMAIL
    [[ "$CERTBOT_EMAIL" == *@* ]] && break
    warn "Please enter a valid email address."
done

# Nextcloud admin credentials
read -rp "$(echo -e "${CYAN}Nextcloud admin username${NC} [admin]: ")" NC_ADMIN_USER
NC_ADMIN_USER="${NC_ADMIN_USER:-admin}"

while true; do
    read -rsp "$(echo -e "${CYAN}Nextcloud admin password${NC}: ")" NC_ADMIN_PASS; echo
    read -rsp "$(echo -e "${CYAN}Confirm password${NC}: ")" NC_ADMIN_PASS2; echo
    [[ "$NC_ADMIN_PASS" == "$NC_ADMIN_PASS2" && -n "$NC_ADMIN_PASS" ]] && break
    warn "Passwords do not match or are empty. Try again."
done

# Database password (auto-generated)
DB_PASS=$(openssl rand -hex 24)
COLLABORA_PASS=$(openssl rand -hex 16)

# Phone region
read -rp "$(echo -e "${CYAN}Country code for phone region${NC} (ISO 3166-1, e.g. IR, DE, US) [US]: ")" PHONE_REGION
PHONE_REGION="${PHONE_REGION:-US}"

# Optional Apps Selection
echo ""
if confirm "Would you like to install Nextcloud Forms alongside the office suite?"; then
    INSTALL_FORMS=true
    info "Nextcloud Forms will be included in the installation queue."
else
    INSTALL_FORMS=false
    info "Skipping Nextcloud Forms app."
fi

# Summary before proceeding
echo ""
info "Configuration summary:"
echo -e "  Nextcloud domain  : ${BOLD}$NEXTCLOUD_DOMAIN${NC}"
echo -e "  Collabora domain  : ${BOLD}$COLLABORA_DOMAIN${NC}"
echo -e "  SSL email         : ${BOLD}$CERTBOT_EMAIL${NC}"
echo -e "  Admin user        : ${BOLD}$NC_ADMIN_USER${NC}"
echo -e "  Phone region      : ${BOLD}$PHONE_REGION${NC}"
echo -e "  DB password       : ${BOLD}[auto-generated]${NC}"
echo -e "  Install Forms     : ${BOLD}$( [[ "$INSTALL_FORMS" == true ]] && echo "Yes" || echo "No" )${NC}"
echo ""

confirm "Proceed with installation?" || exit 0

# ── Create project structure ─────────────────────────────────
header "Step 4 — Project structure"

INSTALL_DIR="$(pwd)/nextcloud"

if [[ -d "$INSTALL_DIR" ]]; then
    warn "Directory '$INSTALL_DIR' already exists."
    confirm "Overwrite?" || error "Aborted. Choose a different directory."
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"/{nginx/conf.d,certbot/www,certbot/conf}
success "Created project structure at $INSTALL_DIR"

# ── Write docker-compose.yml ─────────────────────────────────
header "Step 5 — Writing configuration files"

cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:

  db:
    image: postgres:16-alpine
    container_name: nextcloud_db
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: nextcloud
      POSTGRES_USER: nextcloud
      POSTGRES_PASSWORD: ${DB_PASS}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nextcloud"]
      interval: 30s
      timeout: 10s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: nextcloud_redis
    restart: unless-stopped
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 5

  nextcloud:
    image: nextcloud:29-apache
    container_name: nextcloud_app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - nextcloud_data:/var/www/html
    environment:
      POSTGRES_HOST: db
      POSTGRES_DB: nextcloud
      POSTGRES_USER: nextcloud
      POSTGRES_PASSWORD: ${DB_PASS}
      NEXTCLOUD_ADMIN_USER: ${NC_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: ${NC_ADMIN_PASS}
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_DOMAIN}
      REDIS_HOST: redis
      REDIS_HOST_PORT: 6379

  collabora:
    image: collabora/code:latest
    container_name: collabora_app
    restart: unless-stopped
    environment:
      aliasgroup1: "https://${NEXTCLOUD_DOMAIN/./\\\\.}"
      DONT_GEN_SSL_CERT: "YES"
      extra_params: "--o:ssl.enable=false --o:ssl.termination=true --o:logging.level=warning"
      username: admin
      password: ${COLLABORA_PASS}
    cap_add:
      - MKNOD

  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    restart: unless-stopped
    depends_on:
      - nextcloud
      - collabora
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt

  cron:
    image: nextcloud:29-apache
    container_name: nextcloud_cron
    restart: unless-stopped
    volumes:
      - nextcloud_data:/var/www/html
    entrypoint: /cron.sh
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

volumes:
  postgres_data:
  redis_data:
  nextcloud_data:
EOF

success "docker-compose.yml written"

# ── Write temporary Nginx config (HTTP only for certbot) ──────
cat > "$INSTALL_DIR/nginx/conf.d/nextcloud.conf" << EOF
server {
    listen 80;
    server_name ${NEXTCLOUD_DOMAIN} ${COLLABORA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'nginx is ready';
        add_header Content-Type text/plain;
    }
}
EOF

success "Temporary Nginx config written"

# ── Start Nginx and get SSL certificates ─────────────────────
header "Step 6 — Starting Nginx"

cd "$INSTALL_DIR"
docker compose up -d nginx
sleep 3

# Verify Nginx is responding
if curl -sf --max-time 5 "http://${NEXTCLOUD_DOMAIN}" > /dev/null; then
    success "Nginx is responding on http://${NEXTCLOUD_DOMAIN}"
else
    error "Nginx is not responding. Check DNS — both domains must point to this server's IP."
fi

# ── SSL certificates ─────────────────────────────────────────
header "Step 7 — Obtaining SSL certificates"

docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$CERTBOT_EMAIL" \
    --agree-tos \
    --no-eff-email \
    -d "$NEXTCLOUD_DOMAIN" \
    -d "$COLLABORA_DOMAIN" \
    || error "SSL certificate request failed. Check that both domains resolve to this server."

success "SSL certificates obtained"

# ── Write production Nginx config ────────────────────────────
header "Step 8 — Writing production Nginx config"

# Escape dots in domain for Collabora aliasgroup regex
NEXTCLOUD_DOMAIN_ESCAPED="${NEXTCLOUD_DOMAIN//./\\.}"

cat > "$INSTALL_DIR/nginx/conf.d/nextcloud.conf" << EOF
# ── Nextcloud ──────────────────────────────────────────────
server {
    listen 80;
    server_name ${NEXTCLOUD_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${NEXTCLOUD_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${NEXTCLOUD_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${NEXTCLOUD_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 512M;
    proxy_read_timeout 600s;
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;

    location / {
        proxy_pass http://nextcloud_app:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        proxy_hide_header X-Powered-By;
        proxy_hide_header X-Content-Type-Options;
        proxy_hide_header X-Frame-Options;
        proxy_hide_header X-XSS-Protection;
        proxy_hide_header Strict-Transport-Security;
        proxy_hide_header Referrer-Policy;

        add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer" always;
        add_header X-Proxy "nginx" always;
    }

    location /.well-known/carddav {
        return 301 https://\$host/remote.php/dav;
    }

    location /.well-known/caldav {
        return 301 https://\$host/remote.php/dav;
    }
}

# ── Collabora ──────────────────────────────────────────────
server {
    listen 80;
    server_name ${COLLABORA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${COLLABORA_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${NEXTCLOUD_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${NEXTCLOUD_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
    add_header X-Proxy "nginx" always;

    location / {
        proxy_pass http://collabora_app:9980;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_read_timeout 36000s;
    }
}
EOF

success "Production Nginx config written"

# ── Start full stack ─────────────────────────────────────────
header "Step 9 — Starting full stack"

docker compose up -d

info "Waiting for Nextcloud to completely install and initialize..."
# Loop up to 30 times (5 minutes max), checking every 10 seconds
for i in {1..30}; do
    # Check if occ is ready AND if nextcloud reports itself as installed
    if docker exec -u www-data nextcloud_app php occ status 2>/dev/null | grep -q "installed: true"; then
        success "Nextcloud is fully installed and ready!"
        break
    fi
    
    if [ $i -eq 30 ]; then
        error "Nextcloud installation timed out. Check 'docker logs nextcloud_app'."
    fi
    
    echo -n "."
    sleep 10
done
echo ""

# Reload Nginx with SSL config
docker exec nginx_proxy nginx -t \
    && docker exec nginx_proxy nginx -s reload \
    || error "Nginx config test failed. Check logs: docker logs nginx_proxy"

success "Nginx reloaded with SSL config"

# ── Nextcloud post-install configuration ─────────────────────
header "Step 10 — Nextcloud post-install hardening"

info "Configuring trusted domains..."
# This ensures your domain is explicitly trusted by the system
docker exec -u www-data nextcloud_app php occ config:system:set trusted_domains 1 --value="${NEXTCLOUD_DOMAIN}"

info "Configuring trusted proxies..."
docker exec -u www-data nextcloud_app php occ config:system:delete trusted_proxies 2>/dev/null || true
docker exec -u www-data nextcloud_app php occ config:system:set trusted_proxies 0 --value="172.16.0.0/12"
docker exec -u www-data nextcloud_app php occ config:system:set trusted_proxies 1 --value="10.0.0.0/8"

info "Configuring HTTPS overwrite..."
docker exec -u www-data nextcloud_app php occ config:system:set overwriteprotocol --value="https"
docker exec -u www-data nextcloud_app php occ config:system:set overwrite.cli.url --value="https://${NEXTCLOUD_DOMAIN}"

info "Setting phone region..."
docker exec -u www-data nextcloud_app php occ config:system:set default_phone_region --value="${PHONE_REGION}"

info "Setting maintenance window..."
docker exec -u www-data nextcloud_app php occ config:system:set maintenance_window_start --value="2" --type=integer

info "Setting background jobs to cron..."
docker exec -u www-data nextcloud_app php occ background:cron

info "Running database optimizations..."
docker exec -u www-data nextcloud_app php occ db:add-missing-indices
docker exec -u www-data nextcloud_app php occ db:add-missing-primary-keys

# ── Connect Collabora to Nextcloud ───────────────────────────
header "Step 11 — Connecting Collabora to Nextcloud"

info "Waiting for Collabora to be ready..."
sleep 10

# Download and install the Nextcloud Office (Collabora) app
info "Installing Nextcloud Office app..."
docker exec -u www-data nextcloud_app php occ app:install richdocuments || \
docker exec -u www-data nextcloud_app php occ app:enable richdocuments

# Set Collabora URL in Nextcloud
info "Configuring Collabora URLs..."
docker exec -u www-data nextcloud_app php occ config:app:set richdocuments wopi_url \
    --value="https://${COLLABORA_DOMAIN}"
docker exec -u www-data nextcloud_app php occ config:app:set richdocuments public_wopi_url \
    --value="https://${COLLABORA_DOMAIN}"
docker exec -u www-data nextcloud_app php occ richdocuments:activate-config 2>/dev/null || true

success "Collabora connected to Nextcloud"

# Set Collabora URL in Nextcloud
docker exec -u www-data nextcloud_app php occ config:app:set richdocuments wopi_url \
    --value="https://${COLLABORA_DOMAIN}"
docker exec -u www-data nextcloud_app php occ config:app:set richdocuments public_wopi_url \
    --value="https://${COLLABORA_DOMAIN}"
docker exec -u www-data nextcloud_app php occ richdocuments:activate-config 2>/dev/null || true

success "Collabora connected to Nextcloud"

# ── Optional: Install Nextcloud Forms ────────────────────────
if [ "$INSTALL_FORMS" = true ]; then
    header "Step 11.5 — Installing Nextcloud Forms"
    info "Downloading and installing Forms app package..."
    if docker exec -u www-data nextcloud_app php occ app:install forms; then
        success "Nextcloud Forms app installed and enabled successfully!"
    else
        docker exec -u www-data nextcloud_app php occ app:enable forms \
            && success "Nextcloud Forms app enabled!" \
            || warn "Could not setup Forms automatically. You can add it from the Apps dashboard."
    fi
fi

# ── Auto-renewal cron ────────────────────────────────────────
header "Step 12 — SSL auto-renewal"

CRON_JOB="0 3 * * * cd ${INSTALL_DIR} && docker compose run --rm certbot renew --quiet && docker exec nginx_proxy nginx -s reload"

( crontab -l 2>/dev/null || true ) | awk '!/certbot renew/' | { cat; echo "$CRON_JOB"; } | crontab - >/dev/null 2>&1

success "SSL auto-renewal cron job added (runs daily at 3am)"

# ── Save credentials ─────────────────────────────────────────
header "Step 13 — Saving credentials"

CREDS_FILE="$INSTALL_DIR/.credentials"
cat > "$CREDS_FILE" << EOF
# ============================================================
#  Nextcloud + Collabora — Installation Credentials
#  Generated: $(date)
#  KEEP THIS FILE SECURE — do not commit to git
# ============================================================

NEXTCLOUD_URL=https://${NEXTCLOUD_DOMAIN}
COLLABORA_URL=https://${COLLABORA_DOMAIN}

NEXTCLOUD_ADMIN_USER=${NC_ADMIN_USER}
NEXTCLOUD_ADMIN_PASSWORD=${NC_ADMIN_PASS}

POSTGRES_PASSWORD=${DB_PASS}
COLLABORA_ADMIN_PASSWORD=${COLLABORA_PASS}
EOF

chmod 600 "$CREDS_FILE"
success "Credentials saved to $CREDS_FILE (chmod 600)"

# ── Done ─────────────────────────────────────────────────────
header "Installation complete"

echo -e "${GREEN}${BOLD}"
cat << 'DONE'
  ✓ Nextcloud is running
  ✓ Collabora Online is connected
  ✓ SSL certificates installed
  ✓ Auto-renewal configured
  ✓ Database optimized
  ✓ Security headers set
DONE
echo -e "${NC}"

echo -e "  ${BOLD}Nextcloud :${NC} https://${NEXTCLOUD_DOMAIN}"
echo -e "  ${BOLD}Collabora :${NC} https://${COLLABORA_DOMAIN}"
echo -e "  ${BOLD}Login with:${NC} ${NC_ADMIN_USER} / [see .credentials file]"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  1. Open https://${NEXTCLOUD_DOMAIN} and verify login"
echo -e "  2. Go to Admin → Overview and check for warnings"
echo -e "  3. Configure email in Admin → Basic Settings"
echo -e "  4. Run: docker exec -u www-data nextcloud_app php occ setupchecks"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  View logs    : docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f"
echo -e "  Stop stack   : docker compose -f ${INSTALL_DIR}/docker-compose.yml down"
echo -e "  Start stack  : docker compose -f ${INSTALL_DIR}/docker-compose.yml up -d"
echo ""