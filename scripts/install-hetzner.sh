#!/bin/bash
#
# Moltbot One-Command Installer for Hetzner VPS
#
# Usage (run as root on fresh VPS):
#   curl -fsSL https://get.molt.bot/hetzner | bash
#
# Or with options:
#   curl -fsSL https://get.molt.bot/hetzner | bash -s -- --domain ai.example.com --paranoid
#   curl -fsSL https://get.molt.bot/hetzner | bash -s -- --domain ai.example.com --standard
#
# Options:
#   --domain DOMAIN    Your subdomain (e.g., ai.example.com)
#   --paranoid         Maximum security (Cloudflare Tunnel, no open ports)
#   --standard         Standard security (Caddy reverse proxy)
#   --api-key KEY      Anthropic API key (or set interactively)
#   --user USERNAME    Non-root user to create (default: moltbot)
#   --skip-user        Skip user creation (if already exists)
#   --yes              Skip confirmation prompts
#
set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
VERSION="1.0.0"
REPO_URL="https://raw.githubusercontent.com/moltbot/moltbot/main"
DEFAULT_USER="moltbot"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Options (can be set via flags or interactively)
DOMAIN=""
MODE=""  # "paranoid" or "standard"
API_KEY=""
USERNAME="$DEFAULT_USER"
SKIP_USER=false
AUTO_YES=false

# ============================================================================
# Helpers
# ============================================================================
log() { echo -e "${GREEN}▸${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
success() { echo -e "${GREEN}✓${NC} $1"; }

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}    ${BOLD}Moltbot One-Command Installer${NC}                             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    Secure AI Gateway for Hetzner VPS                         ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

confirm() {
  if [[ "$AUTO_YES" == "true" ]]; then
    return 0
  fi
  read -p "$1 [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

prompt() {
  local var_name=$1
  local prompt_text=$2
  local default=$3
  local secret=${4:-false}

  if [[ "$secret" == "true" ]]; then
    read -sp "$prompt_text" value
    echo
  else
    read -p "$prompt_text" value
  fi

  if [[ -z "$value" && -n "$default" ]]; then
    value="$default"
  fi

  eval "$var_name=\"$value\""
}

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --domain)
        DOMAIN="$2"
        shift 2
        ;;
      --paranoid)
        MODE="paranoid"
        shift
        ;;
      --standard)
        MODE="standard"
        shift
        ;;
      --api-key)
        API_KEY="$2"
        shift 2
        ;;
      --user)
        USERNAME="$2"
        shift 2
        ;;
      --skip-user)
        SKIP_USER=true
        shift
        ;;
      --yes|-y)
        AUTO_YES=true
        shift
        ;;
      --help|-h)
        echo "Moltbot One-Command Installer v$VERSION"
        echo ""
        echo "Usage: curl -fsSL https://get.molt.bot/hetzner | bash -s -- [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --domain DOMAIN    Your subdomain (e.g., ai.example.com)"
        echo "  --paranoid         Maximum security (Cloudflare Tunnel)"
        echo "  --standard         Standard security (Caddy reverse proxy)"
        echo "  --api-key KEY      Anthropic API key"
        echo "  --user USERNAME    Non-root user to create (default: moltbot)"
        echo "  --skip-user        Skip user creation"
        echo "  --yes, -y          Skip confirmation prompts"
        echo ""
        echo "Examples:"
        echo "  # Interactive mode"
        echo "  curl -fsSL https://get.molt.bot/hetzner | bash"
        echo ""
        echo "  # Paranoid mode with domain"
        echo "  curl -fsSL https://get.molt.bot/hetzner | bash -s -- --domain ai.example.com --paranoid"
        echo ""
        echo "  # Standard mode, fully automated"
        echo "  curl -fsSL https://get.molt.bot/hetzner | bash -s -- --domain ai.example.com --standard --api-key sk-ant-... --yes"
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        shift
        ;;
    esac
  done
}

# ============================================================================
# System Checks
# ============================================================================
check_system() {
  log "Checking system requirements..."

  # Check OS
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS. This installer requires Ubuntu or Debian."
  fi

  source /etc/os-release
  if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    error "This installer requires Ubuntu or Debian. Detected: $ID"
  fi

  success "OS: $PRETTY_NAME"

  # Check architecture
  ARCH=$(uname -m)
  if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    error "Unsupported architecture: $ARCH. Requires x86_64 or aarch64."
  fi
  success "Architecture: $ARCH"

  # Check if running as root
  if [[ $EUID -eq 0 ]]; then
    IS_ROOT=true
    success "Running as root (will create non-root user)"
  else
    IS_ROOT=false
    success "Running as user: $(whoami)"
  fi

  # Check internet connectivity
  if ! ping -c 1 github.com &> /dev/null; then
    error "No internet connectivity. Please check your network."
  fi
  success "Internet connectivity OK"
}

# ============================================================================
# Interactive Configuration
# ============================================================================
interactive_config() {
  echo ""
  echo -e "${BOLD}Configuration${NC}"
  echo "─────────────────────────────────────────────"

  # Security mode
  if [[ -z "$MODE" ]]; then
    echo ""
    echo "Security Level:"
    echo "  ${GREEN}1)${NC} Standard  - Caddy reverse proxy, ports 22+443 open"
    echo "  ${GREEN}2)${NC} Paranoid  - Cloudflare Tunnel, only port 22 open (recommended for sensitive data)"
    echo ""
    while true; do
      read -p "Choose security level [1/2]: " choice
      case $choice in
        1) MODE="standard"; break ;;
        2) MODE="paranoid"; break ;;
        *) echo "Please enter 1 or 2" ;;
      esac
    done
  fi
  success "Security mode: $MODE"

  # Domain
  if [[ -z "$DOMAIN" ]]; then
    echo ""
    if [[ "$MODE" == "paranoid" ]]; then
      echo "Domain is ${BOLD}required${NC} for Paranoid mode (Cloudflare Tunnel)."
    else
      echo "Domain is ${BOLD}optional${NC} for Standard mode. Leave empty for localhost-only."
    fi
    read -p "Enter your domain (e.g., ai.example.com): " DOMAIN

    if [[ -z "$DOMAIN" && "$MODE" == "paranoid" ]]; then
      error "Domain is required for Paranoid mode."
    fi
  fi

  if [[ -n "$DOMAIN" ]]; then
    success "Domain: $DOMAIN"
  else
    info "Domain: (none - localhost only)"
  fi

  # API Key
  if [[ -z "$API_KEY" ]]; then
    echo ""
    echo "Enter your Anthropic API key (or press Enter to add later):"
    read -sp "API Key: " API_KEY
    echo
  fi

  if [[ -n "$API_KEY" ]]; then
    success "API Key: ****${API_KEY: -4}"
  else
    info "API Key: (will add later)"
  fi

  # Confirmation
  echo ""
  echo "─────────────────────────────────────────────"
  echo -e "${BOLD}Summary${NC}"
  echo "  Mode:   $MODE"
  echo "  Domain: ${DOMAIN:-"(localhost only)"}"
  echo "  User:   $USERNAME"
  echo "─────────────────────────────────────────────"
  echo ""

  if ! confirm "Proceed with installation?"; then
    echo "Installation cancelled."
    exit 0
  fi
}

# ============================================================================
# Create Non-Root User
# ============================================================================
create_user() {
  if [[ "$IS_ROOT" != "true" ]]; then
    info "Not running as root, skipping user creation"
    return
  fi

  if [[ "$SKIP_USER" == "true" ]]; then
    info "Skipping user creation (--skip-user)"
    return
  fi

  if id "$USERNAME" &>/dev/null; then
    info "User '$USERNAME' already exists"
  else
    log "Creating user '$USERNAME'..."
    adduser --disabled-password --gecos "" "$USERNAME"
    usermod -aG sudo "$USERNAME"

    # Allow passwordless sudo for installation
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
    chmod 440 "/etc/sudoers.d/$USERNAME"

    success "User '$USERNAME' created"
  fi

  # Copy SSH keys
  if [[ -f /root/.ssh/authorized_keys ]]; then
    log "Copying SSH keys to $USERNAME..."
    mkdir -p "/home/$USERNAME/.ssh"
    cp /root/.ssh/authorized_keys "/home/$USERNAME/.ssh/"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
    success "SSH keys copied"
  fi

  # Harden SSH
  log "Hardening SSH configuration..."
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  systemctl restart sshd
  success "SSH hardened (root login disabled)"
}

# ============================================================================
# Install as User
# ============================================================================
install_as_user() {
  local install_script install_args script_path

  if [[ "$MODE" == "paranoid" ]]; then
    install_script="hetzner-install-paranoid.sh"
    install_args="--domain \"$DOMAIN\""
  else
    install_script="hetzner-install.sh"
    install_args="--with-docker"
    if [[ -n "$DOMAIN" ]]; then
      install_args="$install_args --with-caddy --domain \"$DOMAIN\""
    fi
  fi

  log "Downloading installation script..."
  script_path="/tmp/$install_script"
  curl -fsSL "$REPO_URL/scripts/$install_script" -o "$script_path"
  chmod +x "$script_path"

  log "Running installation..."
  if [[ "$IS_ROOT" == "true" ]]; then
    # Run as the created user
    sudo -u "$USERNAME" -i bash -c "cd ~ && $script_path $install_args"
  else
    # Already running as non-root user
    # shellcheck disable=SC2086
    bash "$script_path" $install_args
  fi
}

# ============================================================================
# Post-Install Configuration
# ============================================================================
post_install() {
  local user_home
  if [[ "$IS_ROOT" == "true" ]]; then
    user_home="/home/$USERNAME"
  else
    user_home="$HOME"
  fi

  local env_file="$user_home/.clawdbot/.env"

  # Add API key if provided
  if [[ -n "$API_KEY" ]]; then
    log "Adding API key..."
    if [[ "$IS_ROOT" == "true" ]]; then
      sudo -u "$USERNAME" bash -c "echo 'ANTHROPIC_API_KEY=$API_KEY' >> '$env_file'"
      sudo -u "$USERNAME" chmod 600 "$env_file"
    else
      echo "ANTHROPIC_API_KEY=$API_KEY" >> "$env_file"
      chmod 600 "$env_file"
    fi
    success "API key added"
  fi

  # Start services
  log "Starting services..."
  if [[ "$IS_ROOT" == "true" ]]; then
    sudo -u "$USERNAME" bash -c "systemctl --user start moltbot"
    if [[ "$MODE" == "paranoid" ]]; then
      sudo -u "$USERNAME" bash -c "systemctl --user start cloudflared"
    fi
  else
    systemctl --user start moltbot
    if [[ "$MODE" == "paranoid" ]]; then
      systemctl --user start cloudflared
    fi
  fi
  success "Services started"
}

# ============================================================================
# Final Summary
# ============================================================================
final_summary() {
  local user_home
  if [[ "$IS_ROOT" == "true" ]]; then
    user_home="/home/$USERNAME"
  else
    user_home="$HOME"
  fi

  # Read generated tokens
  local gateway_token=""
  local env_file="$user_home/.clawdbot/.env"
  if [[ -f "$env_file" ]]; then
    gateway_token=$(grep "CLAWDBOT_GATEWAY_TOKEN" "$env_file" 2>/dev/null | cut -d'=' -f2 || true)
  fi

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}    ${BOLD}Installation Complete!${NC}                                    ${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [[ -n "$DOMAIN" ]]; then
    echo -e "  ${BOLD}Access URL:${NC}    https://$DOMAIN"
  else
    echo -e "  ${BOLD}Access URL:${NC}    http://localhost:18789 (via SSH tunnel)"
  fi

  echo ""
  echo -e "  ${BOLD}Configuration:${NC} $user_home/.clawdbot/moltbot.json"
  echo -e "  ${BOLD}Secrets:${NC}       $user_home/.clawdbot/.env"

  if [[ -n "$gateway_token" ]]; then
    echo ""
    echo -e "  ${BOLD}Gateway Token:${NC} $gateway_token"
    echo -e "  ${YELLOW}(Save this token securely - you'll need it to connect)${NC}"
  fi

  echo ""
  echo -e "${BOLD}Next Steps:${NC}"
  echo ""

  if [[ -z "$API_KEY" ]]; then
    echo "  1. Add your API key:"
    echo "     echo 'ANTHROPIC_API_KEY=sk-ant-...' >> $user_home/.clawdbot/.env"
    echo ""
  fi

  echo "  2. Add your user ID to allowlist:"
  echo "     moltbot config set channels.telegram.allowFrom '[\"YOUR_ID\"]'"
  echo ""
  echo "  3. Check status:"
  echo "     systemctl --user status moltbot"
  echo ""
  echo "  4. View logs:"
  echo "     journalctl --user -u moltbot -f"
  echo ""

  if [[ "$IS_ROOT" == "true" ]]; then
    echo -e "${YELLOW}Important:${NC} SSH as '$USERNAME' for future access:"
    echo "     ssh $USERNAME@YOUR_SERVER_IP"
    echo ""
  fi

  echo -e "Documentation: ${CYAN}https://docs.molt.bot/platforms/hetzner${NC}"
  echo ""
}

# ============================================================================
# Main
# ============================================================================
main() {
  parse_args "$@"
  banner
  check_system
  interactive_config
  create_user
  install_as_user
  post_install
  final_summary
}

main "$@"
