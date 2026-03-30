#!/usr/bin/env bash
set -euo pipefail

echo "=== Claude Login ==="
echo ""
echo "1. In another terminal, run:"
echo ""
echo "     npx @anthropic-ai/claude-code setup-token"
echo ""
echo "2. Copy the token it gives you, then paste it below."
echo ""
read -rsp "Token (input hidden): " TOKEN
echo ""

if [ -z "$TOKEN" ]; then
  echo "ERROR: No token provided." >&2
  exit 1
fi

# Store in macOS Keychain — never touches the filesystem
security add-generic-password \
  -a "paperclip-sandbox" \
  -s "paperclip-sandbox-claude-token" \
  -w "$TOKEN" \
  -U 2>/dev/null || \
security add-generic-password \
  -a "paperclip-sandbox" \
  -s "paperclip-sandbox-claude-token" \
  -w "$TOKEN"

echo ""
echo "Done. Token stored in macOS Keychain (service: paperclip-sandbox-claude-token)."
echo "To revoke: visit claude.ai/settings/claude-code"
echo "To delete from Keychain: security delete-generic-password -s paperclip-sandbox-claude-token"
echo ""
echo "Run ./scripts/start.sh to start the sandbox."
