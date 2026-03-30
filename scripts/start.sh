#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"

# Parse args — default to sandbox (allowlist), --open for unrestricted
MODE="sandbox"
EXTRA_ARGS=()
for arg in "$@"; do
  case $arg in
    --open)  MODE="open" ;;
    --help|-h)
      echo "Usage: $0 [--open]"
      echo "  (default)     Network allowlist — only config/allowed-hosts.txt permitted"
      echo "  --open        Full network access (only after security gates pass)"
      exit 0
      ;;
    *)  EXTRA_ARGS+=("$arg") ;;
  esac
done

# Pre-flight
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is not installed." >&2; exit 1
fi
if ! docker info &>/dev/null 2>&1; then
  echo "ERROR: Docker is not running. Start Docker Desktop first." >&2; exit 1
fi
if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo "WARNING: No .env file found. Copy .env.example and add scoped API keys."
  echo "  cp .env.example .env"
  echo ""
fi

# Check Claude auth — Keychain token or ANTHROPIC_API_KEY in .env
if grep -q 'ANTHROPIC_API_KEY=.' "$PROJECT_DIR/.env" 2>/dev/null; then
  echo "  Claude: API key (via .env)"
elif KEYCHAIN_TOKEN=$(security find-generic-password -s "paperclip-sandbox-claude-token" -w 2>/dev/null); then
  export CLAUDE_CODE_OAUTH_TOKEN="$KEYCHAIN_TOKEN"
  echo "  Claude: subscription token (via macOS Keychain)"
else
  echo ""
  echo "  No Claude authentication found. Run:"
  echo ""
  echo "    ./scripts/claude-login.sh"
  echo ""
  exit 1
fi

# Ensure data dir exists
mkdir -p "$PROJECT_DIR/data"

# Clean stale postgres lock only if no sandbox container is currently running
PID_FILE="$PROJECT_DIR/data/instances/default/db/postmaster.pid"
if [ -f "$PID_FILE" ]; then
  if docker compose -f "$DOCKER_DIR/docker-compose.yml" ps --status running 2>/dev/null | grep -q paperclip; then
    echo "  WARNING: Sandbox container is already running. Stop it first with ./scripts/stop.sh"
    exit 1
  else
    echo "  Removing stale postgres PID file (no running container found)"
    rm -f "$PID_FILE"
  fi
fi

# Create run marker for post-run audit
MARKER="/tmp/paperclip-sandbox-marker-$(date +%s)"
touch "$MARKER"
echo "  Audit marker: $MARKER"

# Build compose command
COMPOSE_CMD="docker compose -f $DOCKER_DIR/docker-compose.yml"
case $MODE in
  sandbox)
    COMPOSE_CMD="$COMPOSE_CMD -f $DOCKER_DIR/docker-compose.isolated.yml"
    echo ""
    echo "=== Paperclip Sandbox (allowlist mode) ==="
    echo ""
    echo "  Allowed hosts:"
    while IFS= read -r line; do
      host="${line%%#*}"
      # Trim leading and trailing whitespace but preserve internal spaces (e.g., in 'METHOD URL' rules)
      host="${host#"${host%%[![:space:]]*}"}"
      host="${host%"${host##*[![:space:]]}"}"
      [ -n "$host" ] && echo "    - $host"
    done < "$PROJECT_DIR/config/allowed-hosts.txt"
    echo ""
    echo "  All other outbound traffic is BLOCKED."
    ;;
  open)
    echo ""
    echo "=== Paperclip Sandbox (open mode) ==="
    ;;
esac

echo ""
echo "  Mode:      $MODE"
if [ "$MODE" = "sandbox" ]; then
  echo "  Dashboard: https://localhost:${PAPERCLIP_PORT:-3100}"
  echo "  mitmproxy: http://localhost:8081  (password: p)"
  echo "  Net logs:  docker compose -f $DOCKER_DIR/docker-compose.yml -f $DOCKER_DIR/docker-compose.isolated.yml logs mitmproxy"
else
  echo "  Dashboard: http://localhost:${PAPERCLIP_PORT:-3100}"
fi
echo "  Data dir:  $PROJECT_DIR/data/"
echo ""

$COMPOSE_CMD up --build ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
