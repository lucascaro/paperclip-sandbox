#!/usr/bin/env bash
set -euo pipefail

# Live monitoring of the Paperclip sandbox.
# Shows network connections, resource usage, and process tree.

echo "=== Paperclip Sandbox Monitor ==="
echo "Press Ctrl+C to stop."
echo ""

# Check container is running
CONTAINER_ID=$(docker ps --filter "name=paperclip-sandbox" --format "{{.ID}}" 2>/dev/null || true)
if [ -z "$CONTAINER_ID" ]; then
  echo "ERROR: Paperclip sandbox is not running."
  exit 1
fi

echo "Container: $CONTAINER_ID"
echo ""

while true; do
  clear
  echo "=== Paperclip Sandbox Monitor — $(date '+%H:%M:%S') ==="
  echo ""

  echo "--- Resource Usage ---"
  docker stats --no-stream --format "  CPU: {{.CPUPerc}}  MEM: {{.MemUsage}}  NET: {{.NetIO}}  PIDS: {{.PIDs}}" "$CONTAINER_ID" 2>/dev/null || echo "  (unavailable)"
  echo ""

  echo "--- Container Processes ---"
  docker top "$CONTAINER_ID" -o pid,vsz,rss,comm 2>/dev/null || echo "  (unavailable)"
  echo ""

  echo "--- Host: Listening Ports (node/postgres) ---"
  lsof -i -P -n 2>/dev/null | grep -iE "node|postgres" | grep LISTEN | head -10 || echo "  (none)"
  echo ""

  echo "--- Health ---"
  curl -sf http://localhost:3100/api/health 2>/dev/null && echo "" || echo "  (unhealthy or unreachable)"
  echo ""

  sleep 5
done
