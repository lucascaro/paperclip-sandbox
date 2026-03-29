#!/usr/bin/env bash
set -euo pipefail

# Add a company template to the running Paperclip sandbox.
# Usage: ./scripts/add-company.sh paperclipai/companies/default
#        ./scripts/add-company.sh paperclipai/companies/fullstack-forge

TEMPLATE="${1:-}"

if [ -z "$TEMPLATE" ]; then
  echo "Usage: $0 <company-template>"
  echo ""
  echo "Examples:"
  echo "  $0 paperclipai/companies/default"
  echo "  $0 paperclipai/companies/fullstack-forge"
  echo ""
  echo "Browse templates: https://github.com/paperclipai/companies"
  exit 1
fi

# Check container is running
if ! docker ps --filter "name=paperclip-sandbox" --format "{{.ID}}" | grep -q .; then
  echo "ERROR: Paperclip sandbox is not running. Start it first:"
  echo "  ./scripts/start.sh"
  exit 1
fi

echo "=== Adding company: $TEMPLATE ==="
echo "Running inside container (not on host)..."
echo ""

docker exec -it paperclip-sandbox npx companies.sh add "$TEMPLATE"

echo ""
echo "Company added. Open http://localhost:3100 to manage it."
