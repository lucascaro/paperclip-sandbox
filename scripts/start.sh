#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"

# Parse args
MODE="normal"
for arg in "$@"; do
  case $arg in
    --isolated)  MODE="isolated" ;;
    --proxy)     MODE="proxy" ;;
    --help|-h)
      echo "Usage: $0 [--isolated] [--proxy]"
      echo "  (default)     Start with network access on port 3100"
      echo "  --isolated    Start with NO network (Gate 1)"
      echo "  --proxy       Start with mitmproxy sidecar (Gate 2) — inspect at http://localhost:8081"
      exit 0
      ;;
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
    echo "=== Starting Paperclip Sandbox (ISOLATED — no network) ==="
    ;;
  proxy)
    COMPOSE_CMD="$COMPOSE_CMD -f $DOCKER_DIR/docker-compose.proxy.yml"
    echo "=== Starting Paperclip Sandbox (PROXY — mitmproxy on :8081) ==="
    ;;
  *)
    echo "=== Starting Paperclip Sandbox ==="
    ;;
esac

echo "  Mode:      $MODE"
echo "  Dashboard: http://localhost:3100"
[ "$MODE" = "proxy" ] && echo "  mitmproxy: http://localhost:8081"
echo "  Data dir:  $PROJECT_DIR/data/"
echo "  Marker:    $MARKER"
echo ""

$COMPOSE_CMD up --build "$@"
