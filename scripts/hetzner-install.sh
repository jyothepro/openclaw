#!/bin/bash
#
# Moltbot Secure Installation Script for Hetzner VPS
# This script installs Moltbot and applies all security hardening automatically.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/moltbot/moltbot/main/scripts/hetzner-install.sh | bash
#   # Or download and run with options:
#   ./hetzner-install.sh --with-caddy --domain your-domain.com
#
# Options:
#   --with-caddy        Install Caddy reverse proxy with auto-TLS
#   --domain DOMAIN     Domain for Caddy TLS (required with --with-caddy)
#   --with-docker       Install Docker for sandbox support
#   --skip-node         Skip Node.js installation (if already installed)
#   --channel CHANNEL   Channels to configure (telegram,discord,slack,whatsapp)
#   --help              Show this help message
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
WITH_CADDY=false
WITH_DOCKER=false
SKIP_NODE=false
DOMAIN=""
CHANNELS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --with-caddy)
      WITH_CADDY=true
      shift
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --with-docker)
      WITH_DOCKER=true
      shift
      ;;
    --skip-node)
      SKIP_NODE=true
      shift
      ;;
    --channel)
      CHANNELS="$2"
      shift 2
      ;;
    --help)
      head -25 "$0" | tail -20
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validation
if [[ "$WITH_CADDY" == "true" && -z "$DOMAIN" ]]; then
  echo -e "${RED}Error: --domain is required when using --with-caddy${NC}"
  exit 1
fi

log() {
  echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[!]${NC} $1"
}

error() {
  echo -e "${RED}[✗]${NC} $1"
  exit 1
}

info() {
  echo -e "${BLUE}[i]${NC} $1"
}

header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  error "Do not run this script as root. Run as a regular user with sudo access."
fi

header "Moltbot Secure Installation for Hetzner"

# ============================================================================
# STEP 1: System Prerequisites
# ============================================================================
header "Step 1: Installing System Prerequisites"

info "Updating package lists..."
sudo apt-get update -qq

info "Installing essential packages..."
sudo apt-get install -y -qq curl wget git build-essential

# ============================================================================
# STEP 2: Node.js 22+
# ============================================================================
if [[ "$SKIP_NODE" == "false" ]]; then
  header "Step 2: Installing Node.js 22"

  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "$NODE_VERSION" -ge 22 ]]; then
      log "Node.js $(node -v) already installed"
    else
      warn "Node.js $NODE_VERSION found, upgrading to 22..."
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi
  else
    info "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
  fi

  log "Node.js $(node -v) installed"
else
  log "Skipping Node.js installation"
fi

# ============================================================================
# STEP 3: Docker (Optional)
# ============================================================================
if [[ "$WITH_DOCKER" == "true" ]]; then
  header "Step 3: Installing Docker for Sandboxing"

  if command -v docker &> /dev/null; then
    log "Docker already installed"
  else
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    log "Docker installed (you may need to log out and back in for group changes)"
  fi
else
  info "Skipping Docker installation (sandbox will be limited)"
fi

# ============================================================================
# STEP 4: Install Moltbot
# ============================================================================
header "Step 4: Installing Moltbot"

info "Installing moltbot globally..."
sudo npm install -g moltbot@latest

log "Moltbot $(moltbot --version) installed"

# ============================================================================
# STEP 5: Create Secure Configuration
# ============================================================================
header "Step 5: Creating Secure Configuration"

MOLTBOT_DIR="$HOME/.clawdbot"
mkdir -p "$MOLTBOT_DIR"
chmod 700 "$MOLTBOT_DIR"

# Generate secure tokens
GATEWAY_TOKEN=$(openssl rand -hex 32)
HOOKS_TOKEN=$(openssl rand -hex 32)

# Create .env file with secrets
info "Creating secure .env file..."
cat > "$MOLTBOT_DIR/.env" << EOF
# Moltbot Security Credentials
# Generated: $(date -Iseconds)
# DO NOT COMMIT THIS FILE

# Gateway authentication token
CLAWDBOT_GATEWAY_TOKEN=$GATEWAY_TOKEN

# Webhook authentication token
CLAWDBOT_HOOKS_TOKEN=$HOOKS_TOKEN

# Add your API keys below:
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
EOF
chmod 600 "$MOLTBOT_DIR/.env"
log "Created .env with secure tokens"

# Create hardened configuration
info "Creating hardened moltbot.json..."
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
      "allowInsecureAuth": false
    }
  },

  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "session",
        "workspaceAccess": "ro",
        "docker": {
          "network": "none"
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
      "groupPolicy": "allowlist",
      "allowFrom": []
    },
    "discord": {
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",
      "allowFrom": []
    },
    "slack": {
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",
      "allowFrom": []
    },
    "whatsapp": {
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",
      "allowFrom": []
    },
    "signal": {
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",
      "allowFrom": []
    },
    "imessage": {
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",
      "allowFrom": []
    }
  },

  "tools": {
    "elevated": {
      "enabled": false
    },
    "deny": [
      "system.run"
    ]
  },

  "hooks": {
    "token": "${CLAWDBOT_HOOKS_TOKEN}"
  },

  "logging": {
    "redactSensitive": "tools"
  },

  "session": {
    "dmScope": "per-channel-peer"
  }
}
CONFIGEOF
chmod 600 "$MOLTBOT_DIR/moltbot.json"
log "Created hardened configuration"

# Create workspace directory
mkdir -p "$HOME/moltbot-workspace"
chmod 700 "$HOME/moltbot-workspace"
log "Created workspace directory"

# ============================================================================
# STEP 6: Caddy Reverse Proxy (Optional)
# ============================================================================
if [[ "$WITH_CADDY" == "true" ]]; then
  header "Step 6: Installing Caddy Reverse Proxy"

  if ! command -v caddy &> /dev/null; then
    info "Installing Caddy..."
    sudo apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt-get update -qq
    sudo apt-get install -y -qq caddy
  fi

  info "Configuring Caddy for $DOMAIN..."
  sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
$DOMAIN {
    reverse_proxy 127.0.0.1:18789

    # Rate limiting (requires caddy-ratelimit plugin or use header limits)
    header {
        # Security headers
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    # Logging
    log {
        output file /var/log/caddy/moltbot-access.log
        format json
    }
}
EOF

  sudo mkdir -p /var/log/caddy
  sudo systemctl enable caddy
  sudo systemctl restart caddy
  log "Caddy configured with auto-TLS for $DOMAIN"

  # Update config for trusted proxy
  info "Updating config for reverse proxy..."
  # Use a temp file to modify JSON
  python3 << PYEOF
import json
config_path = "$MOLTBOT_DIR/moltbot.json"
with open(config_path, 'r') as f:
    config = json.load(f)
config['gateway']['trustedProxies'] = ['127.0.0.1']
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
PYEOF
  log "Added trusted proxy configuration"
fi

# ============================================================================
# STEP 7: Systemd Service
# ============================================================================
header "Step 7: Setting Up Systemd Service"

info "Creating systemd user service..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/moltbot.service" << EOF
[Unit]
Description=Moltbot Gateway
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

# Enable lingering for user services to persist after logout
info "Enabling user lingering..."
sudo loginctl enable-linger "$USER"

systemctl --user daemon-reload
systemctl --user enable moltbot
log "Systemd service configured"

# ============================================================================
# STEP 8: Firewall Configuration
# ============================================================================
header "Step 8: Configuring Firewall"

if command -v ufw &> /dev/null; then
  info "Configuring UFW firewall..."
  sudo ufw --force reset > /dev/null 2>&1 || true
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow 22/tcp comment 'SSH'

  if [[ "$WITH_CADDY" == "true" ]]; then
    sudo ufw allow 80/tcp comment 'HTTP (Caddy redirect)'
    sudo ufw allow 443/tcp comment 'HTTPS (Caddy)'
  fi

  # Do NOT expose 18789 - it should only be accessed via localhost or Caddy
  sudo ufw --force enable
  log "Firewall configured (SSH$([ "$WITH_CADDY" == "true" ] && echo ", HTTP, HTTPS"))"
else
  warn "UFW not installed - configure your firewall manually"
  info "Recommended: Block all except SSH (22) and HTTPS (443 if using Caddy)"
fi

# ============================================================================
# STEP 9: Run Security Audit
# ============================================================================
header "Step 9: Running Security Audit"

info "Applying security fixes..."
moltbot security audit --fix 2>/dev/null || true

info "Running security audit..."
moltbot security audit 2>/dev/null || warn "Security audit had warnings (review above)"

# ============================================================================
# STEP 10: Final Summary
# ============================================================================
header "Installation Complete!"

echo ""
echo -e "${GREEN}Moltbot has been installed with security hardening.${NC}"
echo ""
echo "Configuration files:"
echo "  - Config:  $MOLTBOT_DIR/moltbot.json"
echo "  - Secrets: $MOLTBOT_DIR/.env"
echo ""
echo "Important tokens (save these securely):"
echo "  - Gateway Token: $GATEWAY_TOKEN"
echo "  - Hooks Token:   $HOOKS_TOKEN"
echo ""
echo "Next steps:"
echo "  1. Add your API keys to $MOLTBOT_DIR/.env"
echo "     Example: ANTHROPIC_API_KEY=sk-ant-..."
echo ""
echo "  2. Add allowed users to your channel configs:"
echo "     moltbot config set channels.telegram.allowFrom '[\"your-telegram-id\"]'"
echo ""
echo "  3. Start the gateway:"
echo "     systemctl --user start moltbot"
echo ""
echo "  4. Check status:"
echo "     systemctl --user status moltbot"
echo "     moltbot channels status --probe"
echo ""
echo "  5. Run verification script:"
echo "     ./scripts/hetzner-verify.sh"
echo ""
if [[ "$WITH_CADDY" == "true" ]]; then
  echo "  6. Access Control UI at: https://$DOMAIN"
  echo ""
fi
echo -e "${YELLOW}Remember: Add your user IDs to allowFrom before enabling channels!${NC}"
echo ""
