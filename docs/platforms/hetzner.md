---
summary: "Run Moltbot Gateway 24/7 on a Hetzner VPS with full security hardening"
read_when:
  - You want Moltbot running 24/7 on a cloud VPS (not your laptop)
  - You want a production-grade, always-on Gateway on your own VPS
  - You want full control over persistence, binaries, and restart behavior
  - You need maximum security for sensitive data handling
---

# Moltbot on Hetzner VPS

Run a persistent, secure Moltbot Gateway on Hetzner for ~$4-5/month.

---

## One-Command Installation

SSH into your fresh Hetzner VPS as root and run:

```bash
curl -fsSL https://get.molt.bot/hetzner | bash
```

This interactive installer will:
1. Create a secure non-root user
2. Install Node.js, Docker, and Moltbot
3. Configure maximum security settings
4. Set up firewall and services
5. Guide you through domain and API key setup

### Non-Interactive Installation

For automation, pass all options via flags:

```bash
# Paranoid mode (Cloudflare Tunnel, recommended for sensitive data)
curl -fsSL https://get.molt.bot/hetzner | bash -s -- \
  --domain ai.example.com \
  --paranoid \
  --api-key sk-ant-api03-YOUR_KEY \
  --yes

# Standard mode (Caddy reverse proxy)
curl -fsSL https://get.molt.bot/hetzner | bash -s -- \
  --domain ai.example.com \
  --standard \
  --api-key sk-ant-api03-YOUR_KEY \
  --yes
```

### Security Levels

| Level | Open Ports | Best For |
|-------|------------|----------|
| **Standard** | SSH + HTTPS | General use |
| **Paranoid** | SSH only | Sensitive data, maximum security |

**After installation**, add your user ID to the allowlist:

```bash
moltbot config set channels.telegram.allowFrom '["YOUR_TELEGRAM_ID"]'
```

---

## Manual Installation

If you prefer step-by-step control, follow the sections below.

## Prerequisites

- [ ] Hetzner Cloud account ([signup](https://www.hetzner.com/cloud))
- [ ] SSH key pair generated locally
- [ ] Domain with DNS access (optional for Standard, required for Paranoid)
- [ ] Cloudflare account (Paranoid mode only)
- [ ] Anthropic API key (or other LLM provider key)

## Step 1: Create Hetzner VPS

### 1.1 Log into Hetzner Cloud Console

Go to [console.hetzner.cloud](https://console.hetzner.cloud) and create a new project.

### 1.2 Create Server

Click **Add Server** with these settings:

| Setting | Recommended Value |
|---------|-------------------|
| **Location** | Closest to you (e.g., `fsn1`, `nbg1`, `hel1`) |
| **Image** | Ubuntu 24.04 |
| **Type** | CX22 (2 vCPU, 4GB RAM) minimum |
| **Networking** | Public IPv4 ✓, IPv6 ✓ |
| **SSH Key** | Add your public key |
| **Name** | `moltbot` |

### 1.3 Note Your Server IP

Copy the public IPv4 address after creation.

## Step 2: Initial Server Setup

### 2.1 Connect and Create Non-Root User

```bash
# Connect as root
ssh root@YOUR_SERVER_IP

# Create user
adduser moltbot
usermod -aG sudo moltbot

# Copy SSH keys
mkdir -p /home/moltbot/.ssh
cp ~/.ssh/authorized_keys /home/moltbot/.ssh/
chown -R moltbot:moltbot /home/moltbot/.ssh
chmod 700 /home/moltbot/.ssh
chmod 600 /home/moltbot/.ssh/authorized_keys

# Disable root login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Exit and reconnect as moltbot user
exit
```

### 2.2 Reconnect as Non-Root User

```bash
ssh moltbot@YOUR_SERVER_IP
```

## Step 3: Configure DNS (If Using a Domain)

### For Standard Mode (Caddy)

Add an A record in your DNS provider:

| Type | Name | Value |
|------|------|-------|
| A | `ai` (or your subdomain) | `YOUR_SERVER_IP` |

### For Paranoid Mode (Cloudflare Tunnel)

Ensure your domain is on Cloudflare. The script creates DNS records automatically.

## Step 4: Run Installation

### Option A: Standard Mode

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/moltbot/moltbot/main/scripts/hetzner-install.sh -o install.sh
chmod +x install.sh

# With Caddy reverse proxy (recommended)
./install.sh --with-docker --with-caddy --domain ai.example.com

# Or localhost only (SSH tunnel access)
./install.sh --with-docker
```

### Option B: Paranoid Mode (Recommended for Sensitive Data)

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/moltbot/moltbot/main/scripts/hetzner-install-paranoid.sh -o install.sh
chmod +x install.sh

# Run (will prompt for Cloudflare authentication)
./install.sh --domain ai.example.com
```

**What the scripts do:**

1. Install Node.js 22 and Docker
2. Install Moltbot globally
3. Create hardened configuration
4. Generate secure tokens
5. Set up systemd services
6. Configure firewall
7. (Paranoid) Set up Cloudflare Tunnel

## Step 5: Save Your Tokens

The script outputs two tokens. **Save these securely:**

```
Gateway Token: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Hooks Token:   xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Step 6: Add Your API Key

```bash
echo "ANTHROPIC_API_KEY=sk-ant-api03-YOUR_KEY" >> ~/.clawdbot/.env
chmod 600 ~/.clawdbot/.env
```

## Step 7: Configure Allowed Users

All channels are locked to allowlist by default. Add your user IDs:

```bash
# Telegram (get ID from @userinfobot)
moltbot config set channels.telegram.allowFrom '["YOUR_TELEGRAM_ID"]'

# Discord (enable Developer Mode, right-click username, Copy ID)
moltbot config set channels.discord.allowFrom '["YOUR_DISCORD_ID"]'

# WhatsApp (country code + number, no + or spaces)
moltbot config set channels.whatsapp.allowFrom '["1234567890"]'
```

## Step 8: Start Services

```bash
# Start gateway
systemctl --user start moltbot

# Paranoid mode: also start tunnel
systemctl --user start cloudflared

# Check status
systemctl --user status moltbot
```

## Step 9: Verify Installation

```bash
# Download verification script
curl -fsSL https://raw.githubusercontent.com/moltbot/moltbot/main/scripts/hetzner-verify.sh -o verify.sh
chmod +x verify.sh

# Run
./verify.sh
```

Expected output:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Moltbot Security Verification (13 Domains)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Gateway Exposure
  ✓ Gateway bound to loopback (localhost only)
  ✓ Token authentication configured
...
Summary
  ✓ Passed:  18
  ! Warnings: 0
  ✗ Failed:  0

All security checks passed!
```

## Step 10: Connect Channels (Optional)

### Telegram Bot

1. Create bot via [@BotFather](https://t.me/BotFather)
2. Add token:

```bash
moltbot config set channels.telegram.token "YOUR_BOT_TOKEN"
systemctl --user restart moltbot
```

### WhatsApp

```bash
moltbot channels login --channel whatsapp
# Scan QR code
```

---

## Maintenance

### View Logs

```bash
journalctl --user -u moltbot -f
journalctl --user -u cloudflared -f  # Paranoid only
```

### Update Moltbot

```bash
sudo npm install -g moltbot@latest
systemctl --user restart moltbot
```

### Re-run Security Audit

```bash
moltbot security audit --deep
moltbot security audit --fix
```

---

## Security Architecture

### Standard Mode

```
Internet → Caddy (:443) → localhost:18789 → Docker Sandbox
           ↑ TLS          (Gateway)         ↑ network=none
```

### Paranoid Mode

```
Internet → Cloudflare → Tunnel → localhost:18789 → Docker Sandbox
           ↑ DDoS       ↑ outbound (Gateway)       ↑ network=none
           ↑ WAF        ↑ encrypted                ↑ workspace=none
```

---

## Security Checklist

After installation, verify:

- [ ] Gateway bound to localhost (`gateway.bind: loopback`)
- [ ] Authentication token set (`gateway.auth.token`)
- [ ] All channels set to allowlist (`dmPolicy: allowlist`)
- [ ] Groups disabled or allowlisted (`groupPolicy`)
- [ ] Sandbox enabled (`sandbox.mode: all`)
- [ ] Docker network isolated (`docker.network: none`)
- [ ] Elevated tools disabled (`tools.elevated.enabled: false`)
- [ ] File permissions correct (700/600)
- [ ] Firewall active
- [ ] No API keys in config file (use `.env`)

---

## File Locations

| File | Purpose |
|------|---------|
| `~/.clawdbot/moltbot.json` | Main configuration |
| `~/.clawdbot/.env` | API keys and secrets |
| `~/.clawdbot/credentials/` | Channel credentials |
| `~/.clawdbot/sessions/` | Conversation history |
| `~/.config/systemd/user/moltbot.service` | Systemd service |
| `~/.cloudflared/config.yml` | Tunnel config (Paranoid) |

---

## Troubleshooting

### Gateway Won't Start

```bash
journalctl --user -u moltbot --no-pager -n 50
moltbot doctor
```

### Tunnel Not Connecting

```bash
cloudflared tunnel info moltbot
cloudflared tunnel login  # Re-authenticate
```

### Permission Errors

```bash
moltbot security audit --fix
chmod 700 ~/.clawdbot
chmod 600 ~/.clawdbot/moltbot.json ~/.clawdbot/.env
```

---

# Docker Installation (Advanced)

For operators who want full control over the Docker build process.

## Goal

Run a persistent Moltbot Gateway using Docker Compose with durable state and baked-in binaries.

## What you need

- Hetzner VPS with root access
- SSH access from your laptop
- ~20 minutes
- Docker and Docker Compose
- Model auth credentials
- Optional: WhatsApp QR, Telegram bot token, Gmail OAuth  

## Quick Path (Experienced Operators)

1. Provision Hetzner VPS (Ubuntu/Debian)
2. Install Docker
3. Clone Moltbot repository
4. Create persistent host directories
5. Configure `.env` and `docker-compose.yml`
6. Bake required binaries into the image
7. `docker compose up -d`
8. Verify persistence and Gateway access

---

## 1) Provision the VPS

Create an Ubuntu or Debian VPS in Hetzner. Connect as root:

```bash
ssh root@YOUR_VPS_IP
```

---

## 2) Install Docker

```bash
apt-get update
apt-get install -y git curl ca-certificates
curl -fsSL https://get.docker.com | sh
```

Verify:

```bash
docker --version
docker compose version
```

---

## 3) Clone the Moltbot repository

```bash
git clone https://github.com/moltbot/moltbot.git
cd moltbot
```

This guide assumes you will build a custom image to guarantee binary persistence.

---

## 4) Create persistent host directories

Docker containers are ephemeral.
All long-lived state must live on the host.

```bash
mkdir -p /root/.clawdbot
mkdir -p /root/clawd

# Set ownership to the container user (uid 1000):
chown -R 1000:1000 /root/.clawdbot
chown -R 1000:1000 /root/clawd
```

---

## 5) Configure environment variables

Create `.env` in the repository root.

```bash
CLAWDBOT_IMAGE=moltbot:latest
CLAWDBOT_GATEWAY_TOKEN=change-me-now
CLAWDBOT_GATEWAY_BIND=lan
CLAWDBOT_GATEWAY_PORT=18789

CLAWDBOT_CONFIG_DIR=/root/.clawdbot
CLAWDBOT_WORKSPACE_DIR=/root/clawd

GOG_KEYRING_PASSWORD=change-me-now
XDG_CONFIG_HOME=/home/node/.clawdbot
```

Generate strong secrets:

```bash
openssl rand -hex 32
```

**Do not commit this file.**

---

## 6) Docker Compose configuration

Create or update `docker-compose.yml`.

```yaml
services:
  moltbot-gateway:
    image: ${CLAWDBOT_IMAGE}
    build: .
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - CLAWDBOT_GATEWAY_BIND=${CLAWDBOT_GATEWAY_BIND}
      - CLAWDBOT_GATEWAY_PORT=${CLAWDBOT_GATEWAY_PORT}
      - CLAWDBOT_GATEWAY_TOKEN=${CLAWDBOT_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
      - PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    volumes:
      - ${CLAWDBOT_CONFIG_DIR}:/home/node/.clawdbot
      - ${CLAWDBOT_WORKSPACE_DIR}:/home/node/clawd
    ports:
      # Recommended: keep the Gateway loopback-only on the VPS; access via SSH tunnel.
      # To expose it publicly, remove the `127.0.0.1:` prefix and firewall accordingly.
      - "127.0.0.1:${CLAWDBOT_GATEWAY_PORT}:18789"

      # Optional: only if you run iOS/Android nodes against this VPS and need Canvas host.
      # If you expose this publicly, read /gateway/security and firewall accordingly.
      # - "18793:18793"
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "${CLAWDBOT_GATEWAY_BIND}",
        "--port",
        "${CLAWDBOT_GATEWAY_PORT}"
      ]
```

---

## 7) Bake required binaries into the image (critical)

Installing binaries inside a running container is a trap.
Anything installed at runtime will be lost on restart.

All external binaries required by skills must be installed at image build time.

The examples below show three common binaries only:
- `gog` for Gmail access
- `goplaces` for Google Places
- `wacli` for WhatsApp

These are examples, not a complete list.
You may install as many binaries as needed using the same pattern.

If you add new skills later that depend on additional binaries, you must:
1. Update the Dockerfile
2. Rebuild the image
3. Restart the containers

**Example Dockerfile**

```dockerfile
FROM node:22-bookworm

RUN apt-get update && apt-get install -y socat && rm -rf /var/lib/apt/lists/*

# Example binary 1: Gmail CLI
RUN curl -L https://github.com/steipete/gog/releases/latest/download/gog_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog

# Example binary 2: Google Places CLI
RUN curl -L https://github.com/steipete/goplaces/releases/latest/download/goplaces_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces

# Example binary 3: WhatsApp CLI
RUN curl -L https://github.com/steipete/wacli/releases/latest/download/wacli_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/wacli

# Add more binaries below using the same pattern

WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY scripts ./scripts

RUN corepack enable
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

CMD ["node","dist/index.js"]
```

---

## 8) Build and launch

```bash
docker compose build
docker compose up -d moltbot-gateway
```

Verify binaries:

```bash
docker compose exec moltbot-gateway which gog
docker compose exec moltbot-gateway which goplaces
docker compose exec moltbot-gateway which wacli
```

Expected output:

```
/usr/local/bin/gog
/usr/local/bin/goplaces
/usr/local/bin/wacli
```

---

## 9) Verify Gateway

```bash
docker compose logs -f moltbot-gateway
```

Success:

```
[gateway] listening on ws://0.0.0.0:18789
```

From your laptop:

```bash
ssh -N -L 18789:127.0.0.1:18789 root@YOUR_VPS_IP
```

Open:

`http://127.0.0.1:18789/`

Paste your gateway token.

---

## What persists where (source of truth)

Moltbot runs in Docker, but Docker is not the source of truth.
All long-lived state must survive restarts, rebuilds, and reboots.

| Component | Location | Persistence mechanism | Notes |
|---|---|---|---|
| Gateway config | `/home/node/.clawdbot/` | Host volume mount | Includes `moltbot.json`, tokens |
| Model auth profiles | `/home/node/.clawdbot/` | Host volume mount | OAuth tokens, API keys |
| Skill configs | `/home/node/.clawdbot/skills/` | Host volume mount | Skill-level state |
| Agent workspace | `/home/node/clawd/` | Host volume mount | Code and agent artifacts |
| WhatsApp session | `/home/node/.clawdbot/` | Host volume mount | Preserves QR login |
| Gmail keyring | `/home/node/.clawdbot/` | Host volume + password | Requires `GOG_KEYRING_PASSWORD` |
| External binaries | `/usr/local/bin/` | Docker image | Must be baked at build time |
| Node runtime | Container filesystem | Docker image | Rebuilt every image build |
| OS packages | Container filesystem | Docker image | Do not install at runtime |
| Docker container | Ephemeral | Restartable | Safe to destroy |
