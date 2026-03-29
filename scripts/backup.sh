#!/usr/bin/env bash
set -euo pipefail

# Create a timestamped snapshot of the data/ directory.
# Run before upgrades or risky operations.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$PROJECT_DIR/data-backup-$TIMESTAMP.tar.gz"

if [ ! -d "$DATA_DIR" ] || [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
  echo "Nothing to back up — data/ is empty."
  exit 0
fi

echo "=== Backing up Paperclip data ==="
echo "  Source: $DATA_DIR"
echo "  Target: $BACKUP_FILE"

# Stop the server first for a clean backup
RUNNING=$(docker ps --filter "name=paperclip-sandbox" --format "{{.ID}}" 2>/dev/null || true)
if [ -n "$RUNNING" ]; then
  echo ""
  echo "WARNING: Container is running. For a clean backup, stop it first:"
  echo "  ./scripts/stop.sh"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

tar -czf "$BACKUP_FILE" -C "$PROJECT_DIR" data/

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo ""
echo "Backup complete: $BACKUP_FILE ($SIZE)"
