#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")/docker"

echo "=== Stopping Paperclip Sandbox ==="

# Stop all compose profiles
docker compose -f "$DOCKER_DIR/docker-compose.yml" down 2>/dev/null || true
docker compose -f "$DOCKER_DIR/docker-compose.yml" -f "$DOCKER_DIR/docker-compose.proxy.yml" down 2>/dev/null || true

# Check for any leftover containers
LEFTOVER=$(docker ps -q --filter "name=paperclip" 2>/dev/null) || true
if [ -n "$LEFTOVER" ]; then
  echo "Stopping leftover containers..."
  docker stop $LEFTOVER 2>/dev/null || true
fi

# Check host for any escaped processes (should not exist if Docker was used)
HOST_PROCS=$(pgrep -f "paperclip" 2>/dev/null || true)
if [ -n "$HOST_PROCS" ]; then
  echo ""
  echo "WARNING: Paperclip-related processes found on HOST (outside Docker):"
  ps -p "$HOST_PROCS" -o pid,command 2>/dev/null || true
  echo "These were NOT started by this sandbox. Kill manually if unexpected."
fi

echo ""
echo "Sandbox stopped."
echo "Run ./security/audit-run.sh /tmp/paperclip-sandbox-marker-XXXXX to audit."
