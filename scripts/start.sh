#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"

# Parse args
# Default to isolated (allowlist proxy) — require explicit flag for less restrictive modes
MODE="isolated"
EXTRA_ARGS=()
for arg in "$@"; do
  case $arg in
    --open)      MODE="open" ;;
    --proxy)     MODE="proxy" ;;
    --help|-h)
      echo "Usage: $0 [--proxy] [--open]"
      echo "  (default)     Proxy with allowlist — only config/allowed-hosts.txt permitted"
      echo "  --proxy       Proxy monitoring, all traffic allowed — inspect at http://localhost:8081"
      echo "  --open        No proxy, full network access (only after Gates pass)"
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

# Ensure data dir exists
mkdir -p "$PROJECT_DIR/data"

# Create run marker for post-run audit
MARKER="/tmp/paperclip-sandbox-marker-$(date +%s)"
touch "$MARKER"
echo "Audit marker: $MARKER"
echo ""

# Build compose command
COMPOSE_CMD="docker compose -f $DOCKER_DIR/docker-compose.yml"
case $MODE in
  isolated)
    COMPOSE_CMD="$COMPOSE_CMD -f $DOCKER_DIR/docker-compose.isolated.yml"
    echo "=== Starting Paperclip Sandbox (allowlist only) ==="
    echo ""
    echo "  Allowed hosts (config/allowed-hosts.txt):"
    while IFS= read -r line; do
      line="${line%%#*}"   # strip comments
      line="${line// /}"   # trim
      [ -n "$line" ] && echo "    - $line"
    done < "$PROJECT_DIR/config/allowed-hosts.txt"
    echo ""
    echo "  All other outbound traffic is BLOCKED."
    echo "  Inspect traffic at http://localhost:8081"
    ;;
  proxy)
    COMPOSE_CMD="$COMPOSE_CMD -f $DOCKER_DIR/docker-compose.proxy.yml"
    echo "=== Starting Paperclip Sandbox (proxy — all traffic allowed) ==="
    ;;
  open)
    echo "=== Starting Paperclip Sandbox (open — no proxy) ==="
    ;;
esac

echo ""
echo "  Mode:      $MODE"
echo "  Dashboard: http://localhost:3100"
if [ "$MODE" = "isolated" ] || [ "$MODE" = "proxy" ]; then
  echo "  mitmproxy: http://localhost:8081  (password: p)"
fi
echo "  Data dir:  $PROJECT_DIR/data/"
echo "  Marker:    $MARKER"
echo ""

$COMPOSE_CMD up --build ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
