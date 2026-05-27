# ☁️ Nextcloud + Collabora Stack

> A production-ready, self-hosted **Google Drive & Google Docs** alternative powered by Nextcloud and Collabora Online.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Docker](https://img.shields.io/badge/docker-required-blue.svg)

---

## ✨ What You Get

- 📁 **File storage & sync** — your personal Google Drive
- 📝 **Online office suite** — edit Docs, Sheets, and Slides in the browser via Collabora
- 📋 **Nextcloud Forms** — create surveys and forms (optional)
- 🔒 **Automatic SSL** — Let's Encrypt certificates, auto-renewed
- ⚡ **Production-hardened** — Redis caching, PostgreSQL, security headers, cron jobs

---

## 📋 Requirements

- A Linux server (Ubuntu / Debian / RHEL / Rocky)
- Two domains pointing to your server's IP:
  - `cloud.yourdomain.com` → Nextcloud
  - `office.yourdomain.com` → Collabora
- **Docker** and **curl** installed (see below)

---

## 🐳 Step 1 — Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
```

> **Not root?** Add your user to the docker group:
> ```bash
> sudo usermod -aG docker $USER && newgrp docker
> ```

Verify the installation:

```bash
docker --version
docker compose version
```

---

## 🔧 Step 2 — Install curl

Most systems already have it. If not:

```bash
# Debian / Ubuntu
sudo apt install -y curl

# RHEL / Rocky / Fedora
sudo dnf install -y curl
```

---

## 🚀 Step 3 — Run the Installer

```bash
curl -fsSL https://raw.githubusercontent.com/Amin-Shahamiri/nextcloud-collabora-stack/main/install.sh | bash
```

Or download and run manually:

```bash
curl -O https://raw.githubusercontent.com/Amin-Shahamiri/nextcloud-collabora-stack/main/install.sh
chmod +x install.sh
./install.sh
```

The installer will walk you through everything interactively:

1. ✅ Preflight checks
2. 💾 Swap memory setup
3. ⚙️ Configuration (domains, email, admin credentials)
4. 🔐 SSL certificate issuance
5. 🐳 Full Docker stack deployment
6. 🔗 Collabora ↔ Nextcloud integration
7. ⏰ Auto-renewal cron setup

---

## 🗂️ What Gets Deployed

| Service | Image | Role |
|---|---|---|
| `nextcloud_app` | `nextcloud:29-apache` | Main application |
| `collabora_app` | `collabora/code:latest` | Office editing engine |
| `nextcloud_db` | `postgres:16-alpine` | Database |
| `nextcloud_redis` | `redis:7-alpine` | Cache & sessions |
| `nginx_proxy` | `nginx:alpine` | Reverse proxy + SSL |
| `certbot` | `certbot/certbot` | SSL certificate manager |
| `nextcloud_cron` | `nextcloud:29-apache` | Background jobs |

---

## 🛠️ Useful Commands

```bash
# View live logs
docker compose -f nextcloud/docker-compose.yml logs -f

# Stop the stack
docker compose -f nextcloud/docker-compose.yml down

# Start the stack
docker compose -f nextcloud/docker-compose.yml up -d

# Run Nextcloud health checks
docker exec -u www-data nextcloud_app php occ setupchecks
```

---

## 🔑 Credentials

After installation, your credentials are saved to:

```
nextcloud/.credentials
```

> ⚠️ This file has `chmod 600`. Keep it safe and **never commit it to Git**.

---

## 📄 License

MIT — free to use, modify, and distribute.