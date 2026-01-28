#!/bin/bash
#
# Moltbot PARANOID Installation Script for Hetzner VPS
# Maximum security setup with Cloudflare Tunnel (zero exposed ports).
#
# Usage:
#   ./hetzner-install-paranoid.sh --domain ai.jyothepro.com --tunnel-name moltbot
#
# Prerequisites:
#   - Cloudflare account with domain configured
#   - Domain DNS managed by Cloudflare
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Options
DOMAIN=""
TUNNEL_NAME="moltbot"
SKIP_NODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --tunnel-name)
      TUNNEL_NAME="$2"
      shift 2
      ;;
    --skip-node)
      SKIP_NODE=true
      shift
      ;;
    --help)
      echo "Usage: $0 --domain <subdomain.yourdomain.com> [--tunnel-name <name>]"
      echo ""
      echo "Options:"
      echo "  --domain       Your subdomain (e.g., ai.jyothepro.com)"
      echo "  --tunnel-name  Cloudflare tunnel name (default: moltbot)"
      echo "  --skip-node    Skip Node.js installation"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Error: --domain is required${NC}"
  echo "Usage: $0 --domain ai.jyothepro.com"
  exit 1
fi

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

if [[ $EUID -eq 0 ]]; then
  error "Do not run as root. Run as regular user with sudo access."
fi

header "Moltbot PARANOID Installation (Zero Exposed Ports)"

# ============================================================================
# STEP 1: System Prerequisites
# ============================================================================
header "Step 1: System Prerequisites"

info "Updating packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq curl wget git build-essential

# ============================================================================
# STEP 2: Node.js 22
# ============================================================================
if [[ "$SKIP_NODE" == "false" ]]; then
  header "Step 2: Installing Node.js 22"

  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "$NODE_VERSION" -ge 22 ]]; then
      log "Node.js $(node -v) already installed"
    else
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi
  else
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
  fi
  log "Node.js $(node -v) ready"
fi

# ============================================================================
# STEP 3: Docker (Required for Paranoid Mode)
# ============================================================================
header "Step 3: Installing Docker (Required for Sandboxing)"

if command -v docker &> /dev/null; then
  log "Docker already installed"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  warn "Docker installed - you may need to log out/in for group changes"
fi

# ============================================================================
# STEP 4: Cloudflare Tunnel (cloudflared)
# ============================================================================
header "Step 4: Installing Cloudflare Tunnel"

if command -v cloudflared &> /dev/null; then
  log "cloudflared already installed"
else
  info "Installing cloudflared..."

  # Add Cloudflare GPG key and repo
  sudo mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/cloudflared.list

  sudo apt-get update -qq
  sudo apt-get install -y -qq cloudflared
  log "cloudflared installed"
fi

# ============================================================================
# STEP 5: Install Moltbot
# ============================================================================
header "Step 5: Installing Moltbot"

sudo npm install -g moltbot@latest
log "Moltbot $(moltbot --version) installed"

# ============================================================================
# STEP 6: Paranoid Configuration
# ============================================================================
header "Step 6: Creating Paranoid Configuration"

MOLTBOT_DIR="$HOME/.clawdbot"
mkdir -p "$MOLTBOT_DIR"
chmod 700 "$MOLTBOT_DIR"

# Generate secure tokens
GATEWAY_TOKEN=$(openssl rand -hex 32)
HOOKS_TOKEN=$(openssl rand -hex 32)

# Create .env with secrets
cat > "$MOLTBOT_DIR/.env" << EOF
# Moltbot Paranoid Mode Credentials
# Generated: $(date -Iseconds)

CLAWDBOT_GATEWAY_TOKEN=$GATEWAY_TOKEN
CLAWDBOT_HOOKS_TOKEN=$HOOKS_TOKEN

# Add your API keys:
# ANTHROPIC_API_KEY=sk-ant-...
EOF
chmod 600 "$MOLTBOT_DIR/.env"

# Create maximum security configuration
cat > "$MOLTBOT_DIR/moltbot.json" << 'CONFIGEOF'
{
  "$schema": "https://docs.molt.bot/schema/moltbot.json",

  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${CLAWDBOT_GATEWAY_TOKEN}"
    },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": false,
      "dangerouslyDisableDeviceAuth": false
    },
    "nodes": {
      "denyCommands": ["system.run"]
    }
  },

  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "session",
        "workspaceAccess": "none",
        "docker": {
          "network": "none",
          "cpus": "1",
          "memory": "512m"
        }
      }
    },
    "list": [
      {
        "id": "main",
        "default": true,
        "workspace": "~/moltbot-workspace"
      }
    ]
  },

  "channels": {
    "telegram": {
      "dmPolicy": "allowlist",
      "groupPolicy": "disabled",
      "allowFrom": []
    },
    "discord": {
      "dmPolicy": "allowlist",
      "groupPolicy": "disabled",
      "allowFrom": []
    },
    "slack": {
      "dmPolicy": "allowlist",
      "groupPolicy": "disabled",
      "allowFrom": []
    },
    "whatsapp": {
      "dmPolicy": "allowlist",
      "groupPolicy": "disabled",
      "allowFrom": []
    },
    "signal": {
      "dmPolicy": "allowlist",
      "groupPolicy": "disabled",
      "allowFrom": []
    },
    "imessage": {
      "dmPolicy": "allowlist",
      "groupPolicy": "disabled",
      "allowFrom": []
    }
  },

  "tools": {
    "elevated": {
      "enabled": false
    },
    "deny": [
      "system.run",
      "browser.proxy"
    ]
  },

  "hooks": {
    "token": "${CLAWDBOT_HOOKS_TOKEN}"
  },

  "logging": {
    "redactSensitive": "all"
  },

  "session": {
    "dmScope": "per-channel-peer"
  },

  "browser": {
    "enabled": false
  }
}
CONFIGEOF
chmod 600 "$MOLTBOT_DIR/moltbot.json"

# Create isolated workspace
mkdir -p "$HOME/moltbot-workspace"
chmod 700 "$HOME/moltbot-workspace"

log "Paranoid configuration created"

# ============================================================================
# STEP 7: Authenticate Cloudflare Tunnel
# ============================================================================
header "Step 7: Cloudflare Tunnel Authentication"

if [[ ! -f "$HOME/.cloudflared/cert.pem" ]]; then
  info "Opening browser for Cloudflare authentication..."
  echo ""
  echo -e "${YELLOW}IMPORTANT: A browser window will open (or a URL will be shown).${NC}"
  echo -e "${YELLOW}Log in to Cloudflare and authorize the tunnel.${NC}"
  echo ""
  read -p "Press Enter to continue..."

  cloudflared tunnel login
  log "Cloudflare authentication complete"
else
  log "Already authenticated with Cloudflare"
fi

# ============================================================================
# STEP 8: Create Tunnel
# ============================================================================
header "Step 8: Creating Cloudflare Tunnel"

# Check if tunnel exists
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
  warn "Tunnel '$TUNNEL_NAME' already exists"
  TUNNEL_ID=$(cloudflared tunnel list --output json | python3 -c "import sys,json; tunnels=json.load(sys.stdin); print(next((t['id'] for t in tunnels if t['name']=='$TUNNEL_NAME'),''))")
else
  info "Creating tunnel '$TUNNEL_NAME'..."
  cloudflared tunnel create "$TUNNEL_NAME"
  TUNNEL_ID=$(cloudflared tunnel list --output json | python3 -c "import sys,json; tunnels=json.load(sys.stdin); print(next((t['id'] for t in tunnels if t['name']=='$TUNNEL_NAME'),''))")
  log "Tunnel created: $TUNNEL_ID"
fi

# ============================================================================
# STEP 9: Configure Tunnel
# ============================================================================
header "Step 9: Configuring Tunnel"

mkdir -p "$HOME/.cloudflared"

cat > "$HOME/.cloudflared/config.yml" << EOF
tunnel: $TUNNEL_NAME
credentials-file: $HOME/.cloudflared/${TUNNEL_ID}.json

ingress:
  # Main gateway (Control UI + API)
  - hostname: $DOMAIN
    service: http://localhost:18789
    originRequest:
      noTLSVerify: false
      connectTimeout: 30s
      tcpKeepAlive: 30s
      keepAliveConnections: 100
      keepAliveTimeout: 90s
      # WebSocket support
      httpHostHeader: $DOMAIN

  # Catch-all (required)
  - service: http_status:404
EOF
chmod 600 "$HOME/.cloudflared/config.yml"

log "Tunnel configuration created"

# ============================================================================
# STEP 10: Route DNS
# ============================================================================
header "Step 10: Routing DNS"

info "Creating DNS route for $DOMAIN..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null || warn "DNS route may already exist"
log "DNS routed: $DOMAIN → tunnel"

# ============================================================================
# STEP 11: Systemd Services
# ============================================================================
header "Step 11: Setting Up Services"

mkdir -p "$HOME/.config/systemd/user"

# Moltbot Gateway Service
cat > "$HOME/.config/systemd/user/moltbot.service" << EOF
[Unit]
Description=Moltbot Gateway (Paranoid Mode)
After=network.target

[Service]
Type=simple
WorkingDirectory=$HOME
ExecStart=$(which moltbot) gateway run --bind loopback --port 18789
Restart=always
RestartSec=5
Environment=HOME=$HOME
EnvironmentFile=$MOLTBOT_DIR/.env

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
EOF

# Cloudflare Tunnel Service
cat > "$HOME/.config/systemd/user/cloudflared.service" << EOF
[Unit]
Description=Cloudflare Tunnel
After=network-online.target moltbot.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(which cloudflared) tunnel run $TUNNEL_NAME
Restart=always
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

# Enable lingering
sudo loginctl enable-linger "$USER"

# Reload and enable services
systemctl --user daemon-reload
systemctl --user enable moltbot cloudflared

log "Services configured"

# ============================================================================
# STEP 12: Firewall - LOCK DOWN EVERYTHING
# ============================================================================
header "Step 12: Hardening Firewall (Paranoid Mode)"

if command -v ufw &> /dev/null; then
  info "Configuring UFW for maximum security..."

  sudo ufw --force reset > /dev/null 2>&1 || true
  sudo ufw default deny incoming
  sudo ufw default allow outgoing

  # ONLY SSH - nothing else!
  sudo ufw allow 22/tcp comment 'SSH only'

  # Explicitly deny common ports
  sudo ufw deny 80/tcp
  sudo ufw deny 443/tcp
  sudo ufw deny 18789/tcp

  sudo ufw --force enable
  log "Firewall locked down (SSH only)"

  echo ""
  echo -e "${GREEN}Firewall status:${NC}"
  sudo ufw status verbose
else
  warn "UFW not found - manually configure firewall to allow SSH only"
fi

# ============================================================================
# STEP 13: Security Audit
# ============================================================================
header "Step 13: Final Security Audit"

moltbot security audit --fix 2>/dev/null || true
moltbot security audit 2>/dev/null || warn "Review audit output above"

# ============================================================================
# STEP 14: Verification
# ============================================================================
header "Step 14: Verifying Setup"

echo ""
echo "Checking open ports..."
if command -v ss &> /dev/null; then
  OPEN_PORTS=$(ss -tlnp 2>/dev/null | grep -E "0\.0\.0\.0|::" | grep -v "127\." || true)
  if [[ -z "$OPEN_PORTS" ]]; then
    log "No ports exposed to internet (perfect!)"
  else
    warn "Some ports may be exposed:"
    echo "$OPEN_PORTS"
  fi
fi

echo ""
echo "Checking tunnel status..."
cloudflared tunnel info "$TUNNEL_NAME" 2>/dev/null || info "Tunnel info will be available after start"

# ============================================================================
# SUMMARY
# ============================================================================
header "Installation Complete - PARANOID MODE"

echo ""
echo -e "${GREEN}Your Moltbot is configured for maximum security:${NC}"
echo ""
echo "  ✓ Gateway bound to localhost only"
echo "  ✓ All traffic through Cloudflare Tunnel (encrypted)"
echo "  ✓ No ports exposed (except SSH)"
echo "  ✓ Full Docker sandboxing with network isolation"
echo "  ✓ All channels locked to allowlist"
echo "  ✓ Groups disabled by default"
echo "  ✓ Elevated tools disabled"
echo "  ✓ Browser control disabled"
echo "  ✓ Full log redaction enabled"
echo ""
echo "Access URL: https://$DOMAIN"
echo ""
echo "Tokens (save securely):"
echo "  Gateway: $GATEWAY_TOKEN"
echo "  Hooks:   $HOOKS_TOKEN"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "  1. Add your API key:"
echo "     echo 'ANTHROPIC_API_KEY=sk-ant-...' >> ~/.clawdbot/.env"
echo ""
echo "  2. Add your user ID to allowlist:"
echo "     moltbot config set channels.telegram.allowFrom '[\"your-id\"]'"
echo ""
echo "  3. Start services:"
echo "     systemctl --user start moltbot"
echo "     systemctl --user start cloudflared"
echo ""
echo "  4. Verify tunnel:"
echo "     cloudflared tunnel info $TUNNEL_NAME"
echo "     curl -I https://$DOMAIN"
echo ""
echo "  5. Run verification:"
echo "     ./scripts/hetzner-verify.sh"
echo ""
echo -e "${BLUE}Security architecture:${NC}"
echo ""
echo "  Internet → Cloudflare (DDoS protection, WAF)"
echo "           → Tunnel (encrypted, outbound-only)"
echo "           → localhost:18789 (Gateway)"
echo "           → Docker sandbox (isolated network)"
echo ""
echo -e "${RED}Remember: Your VPS has NO open ports except SSH!${NC}"
echo ""
