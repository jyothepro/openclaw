#!/bin/bash
#
# Moltbot Security Verification Script for Hetzner VPS
# Verifies all 13 security domains are properly configured.
#
# Usage:
#   ./hetzner-verify.sh
#   ./hetzner-verify.sh --verbose
#   ./hetzner-verify.sh --json
#
set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

# Options
VERBOSE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--verbose] [--json]"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# Counters
PASS=0
WARN=0
FAIL=0
CHECKS=()

# Config paths
MOLTBOT_DIR="${CLAWDBOT_STATE_DIR:-$HOME/.clawdbot}"
CONFIG_FILE="$MOLTBOT_DIR/moltbot.json"
ENV_FILE="$MOLTBOT_DIR/.env"

# Helper functions
pass() {
  ((PASS++))
  CHECKS+=("{\"domain\":\"$1\",\"status\":\"pass\",\"message\":\"$2\"}")
  if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo -e "  ${GREEN}✓${NC} $2"
  fi
}

warn() {
  ((WARN++))
  CHECKS+=("{\"domain\":\"$1\",\"status\":\"warn\",\"message\":\"$2\"}")
  if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo -e "  ${YELLOW}!${NC} $2"
  fi
}

fail() {
  ((FAIL++))
  CHECKS+=("{\"domain\":\"$1\",\"status\":\"fail\",\"message\":\"$2\"}")
  if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo -e "  ${RED}✗${NC} $2"
  fi
}

info() {
  if [[ "$VERBOSE" == "true" && "$JSON_OUTPUT" == "false" ]]; then
    echo -e "  ${GRAY}  → $1${NC}"
  fi
}

header() {
  if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo ""
    echo -e "${BOLD}$1${NC}"
  fi
}

# Check if config exists
check_config_exists() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found at $CONFIG_FILE${NC}"
    echo "Run the install script first: ./scripts/hetzner-install.sh"
    exit 1
  fi
}

# Read JSON value using python (more reliable than jq for nested values)
read_config() {
  python3 -c "
import json
import sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    keys = '$1'.split('.')
    value = config
    for key in keys:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            value = None
            break
    if value is None:
        print('')
    elif isinstance(value, bool):
        print(str(value).lower())
    elif isinstance(value, (dict, list)):
        print(json.dumps(value))
    else:
        print(value)
except:
    print('')
" 2>/dev/null
}

# ============================================================================
# DOMAIN 1: Gateway Exposure
# ============================================================================
check_gateway_exposure() {
  header "1. Gateway Exposure"

  local bind=$(read_config "gateway.bind")
  local auth_mode=$(read_config "gateway.auth.mode")
  local auth_token=$(read_config "gateway.auth.token")
  local auth_password=$(read_config "gateway.auth.password")

  # Check bind mode
  if [[ "$bind" == "loopback" || -z "$bind" ]]; then
    pass "gateway_bind" "Gateway bound to loopback (localhost only)"
  elif [[ "$bind" == "lan" ]]; then
    if [[ -n "$auth_mode" && ("$auth_mode" == "token" || "$auth_mode" == "password") ]]; then
      if [[ -n "$auth_token" || -n "$auth_password" ]]; then
        warn "gateway_bind" "Gateway bound to 0.0.0.0 (protected by auth)"
      else
        fail "gateway_bind" "Gateway bound to 0.0.0.0 WITHOUT authentication!"
      fi
    else
      fail "gateway_bind" "Gateway bound to 0.0.0.0 WITHOUT authentication!"
    fi
  else
    pass "gateway_bind" "Gateway bound to: $bind"
  fi

  # Check auth configuration
  if [[ -n "$auth_mode" ]]; then
    if [[ "$auth_mode" == "token" && -n "$auth_token" ]]; then
      pass "gateway_auth" "Token authentication configured"
    elif [[ "$auth_mode" == "password" && -n "$auth_password" ]]; then
      pass "gateway_auth" "Password authentication configured"
    else
      warn "gateway_auth" "Auth mode set but credentials may be missing"
    fi
  else
    if [[ "$bind" == "loopback" || -z "$bind" ]]; then
      info "No auth required for loopback-only binding"
    else
      fail "gateway_auth" "No authentication configured for non-loopback binding"
    fi
  fi
}

# ============================================================================
# DOMAIN 2: DM Policy
# ============================================================================
check_dm_policy() {
  header "2. DM Policy"

  local channels=("telegram" "discord" "slack" "whatsapp" "signal" "imessage")

  for channel in "${channels[@]}"; do
    local policy=$(read_config "channels.$channel.dmPolicy")
    local allow_from=$(read_config "channels.$channel.allowFrom")

    if [[ -z "$policy" ]]; then
      info "$channel: Using default (pairing)"
      continue
    fi

    case "$policy" in
      "allowlist")
        pass "dm_$channel" "$channel DM policy: allowlist (strict)"
        ;;
      "pairing")
        pass "dm_$channel" "$channel DM policy: pairing (approval required)"
        ;;
      "open")
        if [[ "$allow_from" == *'"*"'* ]]; then
          fail "dm_$channel" "$channel DM policy: OPEN to anyone!"
        else
          warn "dm_$channel" "$channel DM policy: open (check allowFrom)"
        fi
        ;;
      "disabled")
        pass "dm_$channel" "$channel DM policy: disabled"
        ;;
      *)
        warn "dm_$channel" "$channel DM policy: unknown ($policy)"
        ;;
    esac
  done
}

# ============================================================================
# DOMAIN 3: Group Access Control
# ============================================================================
check_group_policy() {
  header "3. Group Access Control"

  local channels=("telegram" "discord" "slack" "whatsapp" "signal" "imessage")

  for channel in "${channels[@]}"; do
    local policy=$(read_config "channels.$channel.groupPolicy")

    if [[ -z "$policy" ]]; then
      # Check defaults - iMessage and Slack default to open
      if [[ "$channel" == "imessage" || "$channel" == "slack" ]]; then
        warn "group_$channel" "$channel group policy: DEFAULT (open) - should set explicitly"
      else
        info "$channel: Using default (allowlist)"
      fi
      continue
    fi

    case "$policy" in
      "allowlist")
        pass "group_$channel" "$channel group policy: allowlist"
        ;;
      "open")
        warn "group_$channel" "$channel group policy: open (anyone can trigger)"
        ;;
      "disabled")
        pass "group_$channel" "$channel group policy: disabled"
        ;;
      *)
        warn "group_$channel" "$channel group policy: $policy"
        ;;
    esac
  done
}

# ============================================================================
# DOMAIN 4: Credentials Security
# ============================================================================
check_credentials() {
  header "4. Credentials Security"

  # Check .env file
  if [[ -f "$ENV_FILE" ]]; then
    local env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %Lp "$ENV_FILE" 2>/dev/null)
    if [[ "$env_perms" == "600" ]]; then
      pass "env_perms" ".env file permissions: 600 (secure)"
    else
      fail "env_perms" ".env file permissions: $env_perms (should be 600)"
    fi
  else
    warn "env_file" ".env file not found (secrets may be in config)"
  fi

  # Check config file permissions
  if [[ -f "$CONFIG_FILE" ]]; then
    local config_perms=$(stat -c %a "$CONFIG_FILE" 2>/dev/null || stat -f %Lp "$CONFIG_FILE" 2>/dev/null)
    if [[ "$config_perms" == "600" ]]; then
      pass "config_perms" "Config file permissions: 600 (secure)"
    else
      fail "config_perms" "Config file permissions: $config_perms (should be 600)"
    fi
  fi

  # Check state directory permissions
  local dir_perms=$(stat -c %a "$MOLTBOT_DIR" 2>/dev/null || stat -f %Lp "$MOLTBOT_DIR" 2>/dev/null)
  if [[ "$dir_perms" == "700" ]]; then
    pass "dir_perms" "State directory permissions: 700 (secure)"
  else
    warn "dir_perms" "State directory permissions: $dir_perms (should be 700)"
  fi

  # Check for plaintext secrets in config
  if grep -q "sk-ant-\|sk-\|xoxb-\|xoxp-" "$CONFIG_FILE" 2>/dev/null; then
    warn "plaintext_secrets" "Possible API keys in config (use .env instead)"
  else
    pass "plaintext_secrets" "No obvious API keys in config file"
  fi
}

# ============================================================================
# DOMAIN 5: Browser Control Exposure
# ============================================================================
check_browser_control() {
  header "5. Browser Control Exposure"

  local browser_enabled=$(read_config "browser.enabled")
  local cdp_url=$(read_config "browser.cdpUrl")

  if [[ "$browser_enabled" == "false" ]]; then
    pass "browser" "Browser control disabled"
    return
  fi

  if [[ -n "$cdp_url" ]]; then
    if [[ "$cdp_url" == *"localhost"* || "$cdp_url" == *"127.0.0.1"* ]]; then
      pass "browser_cdp" "Browser CDP on localhost"
    elif [[ "$cdp_url" == *"https://"* ]]; then
      pass "browser_cdp" "Browser CDP using HTTPS"
    else
      warn "browser_cdp" "Browser CDP URL may be insecure: $cdp_url"
    fi
  else
    info "Browser CDP using default (localhost)"
  fi
}

# ============================================================================
# DOMAIN 6: Gateway Bind & Network
# ============================================================================
check_network() {
  header "6. Gateway Bind & Network"

  local trusted_proxies=$(read_config "gateway.trustedProxies")

  # Check if behind reverse proxy
  if systemctl is-active --quiet caddy 2>/dev/null || systemctl is-active --quiet nginx 2>/dev/null; then
    if [[ -n "$trusted_proxies" && "$trusted_proxies" != "[]" ]]; then
      pass "trusted_proxies" "Trusted proxies configured for reverse proxy"
    else
      warn "trusted_proxies" "Reverse proxy detected but trustedProxies not set"
    fi
  else
    info "No reverse proxy detected"
  fi

  # Check listening ports
  local gateway_port=$(read_config "gateway.port")
  gateway_port=${gateway_port:-18789}

  if ss -tlnp 2>/dev/null | grep -q ":$gateway_port.*0.0.0.0"; then
    fail "port_exposure" "Gateway port $gateway_port exposed on 0.0.0.0"
  elif ss -tlnp 2>/dev/null | grep -q ":$gateway_port.*127.0.0.1"; then
    pass "port_exposure" "Gateway port $gateway_port bound to localhost only"
  else
    info "Gateway may not be running (port $gateway_port not listening)"
  fi
}

# ============================================================================
# DOMAIN 7: Tool Access & Sandboxing
# ============================================================================
check_sandboxing() {
  header "7. Tool Access & Sandboxing"

  local sandbox_mode=$(read_config "agents.defaults.sandbox.mode")
  local docker_network=$(read_config "agents.defaults.sandbox.docker.network")
  local elevated=$(read_config "tools.elevated.enabled")
  local tool_deny=$(read_config "tools.deny")

  # Check sandbox mode
  if [[ "$sandbox_mode" == "all" ]]; then
    pass "sandbox_mode" "Sandbox mode: all (full sandboxing)"
  elif [[ "$sandbox_mode" == "non-main" ]]; then
    pass "sandbox_mode" "Sandbox mode: non-main (groups sandboxed)"
  elif [[ -z "$sandbox_mode" || "$sandbox_mode" == "off" ]]; then
    fail "sandbox_mode" "Sandbox mode: OFF (no sandboxing!)"
  else
    warn "sandbox_mode" "Sandbox mode: $sandbox_mode"
  fi

  # Check Docker network isolation
  if [[ "$docker_network" == "none" ]]; then
    pass "docker_network" "Docker network: none (isolated)"
  elif [[ -n "$docker_network" ]]; then
    warn "docker_network" "Docker network: $docker_network (not isolated)"
  else
    if [[ "$sandbox_mode" == "all" || "$sandbox_mode" == "non-main" ]]; then
      warn "docker_network" "Docker network not explicitly set to 'none'"
    fi
  fi

  # Check elevated tools
  if [[ "$elevated" == "false" ]]; then
    pass "elevated_tools" "Elevated tools: disabled"
  elif [[ "$elevated" == "true" || -z "$elevated" ]]; then
    warn "elevated_tools" "Elevated tools: enabled (default)"
  fi

  # Check tool denials
  if [[ -n "$tool_deny" && "$tool_deny" != "[]" ]]; then
    pass "tool_deny" "Tool deny list configured"
  else
    warn "tool_deny" "No tools explicitly denied"
  fi
}

# ============================================================================
# DOMAIN 8: File Permissions & Disk
# ============================================================================
check_file_permissions() {
  header "8. File Permissions & Disk"

  # Check credentials directory
  local creds_dir="$MOLTBOT_DIR/credentials"
  if [[ -d "$creds_dir" ]]; then
    local creds_perms=$(stat -c %a "$creds_dir" 2>/dev/null || stat -f %Lp "$creds_dir" 2>/dev/null)
    if [[ "$creds_perms" == "700" ]]; then
      pass "creds_dir" "Credentials directory: 700"
    else
      warn "creds_dir" "Credentials directory: $creds_perms (should be 700)"
    fi

    # Check individual credential files
    local insecure_files=0
    local f f_perms
    shopt -s nullglob
    for f in "$creds_dir"/*.json; do
      if [[ -f "$f" ]]; then
        f_perms=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null)
        if [[ "$f_perms" != "600" ]]; then
          ((insecure_files++))
          info "$(basename "$f"): $f_perms (should be 600)"
        fi
      fi
    done
    shopt -u nullglob

    if [[ $insecure_files -eq 0 ]]; then
      pass "cred_files" "All credential files have correct permissions"
    else
      warn "cred_files" "$insecure_files credential file(s) have loose permissions"
    fi
  else
    info "No credentials directory yet"
  fi

  # Check for world-readable files
  local world_readable=$(find "$MOLTBOT_DIR" -type f -perm -004 2>/dev/null | wc -l)
  if [[ $world_readable -eq 0 ]]; then
    pass "world_readable" "No world-readable files in state directory"
  else
    fail "world_readable" "$world_readable world-readable file(s) found"
  fi
}

# ============================================================================
# DOMAIN 9: Plugin Trust & Model
# ============================================================================
check_plugins() {
  header "9. Plugin Trust & Model"

  local plugins_allow=$(read_config "plugins.allow")
  local extensions_dir="$MOLTBOT_DIR/extensions"

  if [[ -n "$plugins_allow" && "$plugins_allow" != "[]" ]]; then
    pass "plugin_allowlist" "Plugin allowlist configured"
  else
    if [[ -d "$extensions_dir" ]] && [[ -n "$(ls -A "$extensions_dir" 2>/dev/null)" ]]; then
      warn "plugin_allowlist" "Plugins installed but no explicit allowlist"
    else
      info "No plugins installed"
    fi
  fi
}

# ============================================================================
# DOMAIN 10: Logging & Redaction
# ============================================================================
check_logging() {
  header "10. Logging & Redaction"

  local redact=$(read_config "logging.redactSensitive")

  if [[ "$redact" == "tools" || -z "$redact" ]]; then
    pass "redaction" "Sensitive data redaction: enabled (tools)"
  elif [[ "$redact" == "all" ]]; then
    pass "redaction" "Sensitive data redaction: all"
  elif [[ "$redact" == "off" ]]; then
    fail "redaction" "Sensitive data redaction: OFF"
  else
    warn "redaction" "Sensitive data redaction: $redact"
  fi
}

# ============================================================================
# DOMAIN 11: Prompt Injection
# ============================================================================
check_prompt_injection() {
  header "11. Prompt Injection Defense"

  # This is code-level, so we just verify the protection exists
  if [[ -f "$(dirname "$0")/../src/security/external-content.ts" ]] || command -v moltbot &>/dev/null; then
    pass "injection_defense" "External content wrapping available (code-level)"
  fi

  # Check DM policies as primary defense
  local open_channels=0
  for channel in telegram discord slack whatsapp signal imessage; do
    local policy=$(read_config "channels.$channel.dmPolicy")
    if [[ "$policy" == "open" ]]; then
      ((open_channels++))
    fi
  done

  if [[ $open_channels -eq 0 ]]; then
    pass "injection_surface" "No channels with open DM policy"
  else
    warn "injection_surface" "$open_channels channel(s) with open DM policy (injection risk)"
  fi
}

# ============================================================================
# DOMAIN 12: Dangerous Commands
# ============================================================================
check_dangerous_commands() {
  header "12. Dangerous Commands"

  local tool_deny=$(read_config "tools.deny")
  local node_deny=$(read_config "gateway.nodes.denyCommands")

  if [[ "$tool_deny" == *"system.run"* ]]; then
    pass "system_run" "system.run in tool deny list"
  else
    warn "system_run" "system.run not explicitly denied"
  fi

  if [[ -n "$node_deny" && "$node_deny" != "[]" ]]; then
    pass "node_deny" "Node command deny list configured"
  else
    info "No explicit node command denials"
  fi
}

# ============================================================================
# DOMAIN 13: Secret Scanning
# ============================================================================
check_secret_scanning() {
  header "13. Secret Scanning"

  # Check if detect-secrets baseline exists (for dev environments)
  if [[ -f ".secrets.baseline" ]]; then
    pass "detect_secrets" "detect-secrets baseline found"
  else
    info "detect-secrets baseline not found (OK for production)"
  fi

  # Check if any obvious secrets in common locations
  local secret_patterns="sk-ant-|sk-proj-|xoxb-|xoxp-|ghp_|gho_|AKIA"

  if grep -rE "$secret_patterns" "$MOLTBOT_DIR"/*.json 2>/dev/null | grep -v ".env" | head -1 > /dev/null; then
    warn "secrets_in_config" "Possible secrets found in config files"
  else
    pass "secrets_in_config" "No obvious secrets in config files"
  fi
}

# ============================================================================
# RUN MOLTBOT SECURITY AUDIT
# ============================================================================
run_moltbot_audit() {
  header "Moltbot Built-in Security Audit"

  if command -v moltbot &>/dev/null; then
    info "Running moltbot security audit..."
    if moltbot security audit 2>&1 | grep -q "passed\|clean\|secure"; then
      pass "moltbot_audit" "moltbot security audit passed"
    else
      warn "moltbot_audit" "moltbot security audit reported issues (review above)"
    fi
  else
    warn "moltbot_audit" "moltbot command not found"
  fi
}

# ============================================================================
# SERVICE STATUS
# ============================================================================
check_services() {
  header "Service Status"

  # Check moltbot service
  if systemctl --user is-active --quiet moltbot 2>/dev/null; then
    pass "moltbot_service" "Moltbot service: running"
  else
    warn "moltbot_service" "Moltbot service: not running"
  fi

  # Check Caddy
  if systemctl is-active --quiet caddy 2>/dev/null; then
    pass "caddy_service" "Caddy service: running"
  else
    info "Caddy service: not running (may not be installed)"
  fi

  # Check firewall
  if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    pass "firewall" "UFW firewall: active"
  else
    warn "firewall" "UFW firewall: not active"
  fi
}

# ============================================================================
# MAIN
# ============================================================================
main() {
  if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Moltbot Security Verification (13 Domains)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  fi

  check_config_exists

  check_gateway_exposure
  check_dm_policy
  check_group_policy
  check_credentials
  check_browser_control
  check_network
  check_sandboxing
  check_file_permissions
  check_plugins
  check_logging
  check_prompt_injection
  check_dangerous_commands
  check_secret_scanning
  check_services

  # Summary
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "{"
    echo "  \"summary\": {\"pass\": $PASS, \"warn\": $WARN, \"fail\": $FAIL},"
    echo "  \"checks\": ["
    local first=true
    for check in "${CHECKS[@]}"; do
      if [[ "$first" == "true" ]]; then
        first=false
      else
        echo ","
      fi
      echo -n "    $check"
    done
    echo ""
    echo "  ]"
    echo "}"
  else
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Passed:${NC}  $PASS"
    echo -e "  ${YELLOW}! Warnings:${NC} $WARN"
    echo -e "  ${RED}✗ Failed:${NC}  $FAIL"
    echo ""

    if [[ $FAIL -gt 0 ]]; then
      echo -e "${RED}Security issues detected! Review failed checks above.${NC}"
      echo ""
      echo "Quick fixes:"
      echo "  moltbot security audit --fix"
      echo "  chmod 600 $CONFIG_FILE $ENV_FILE"
      echo "  chmod 700 $MOLTBOT_DIR"
      exit 1
    elif [[ $WARN -gt 0 ]]; then
      echo -e "${YELLOW}Some warnings detected. Review and address if needed.${NC}"
      exit 0
    else
      echo -e "${GREEN}All security checks passed!${NC}"
      exit 0
    fi
  fi
}

main
