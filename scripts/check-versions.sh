#!/usr/bin/env bash
set -euo pipefail

# check-versions.sh — Compare pinned versions against latest available.
# Shows whether an upgrade is available and reminds you to re-run trust gates.

echo "=== Paperclip Sandbox — Version Check ==="
echo ""

# Pinned versions (must match Dockerfile ARGs and VERSIONS.md)
PINNED_COMPANIES_SH="2026.325.2"
PINNED_PAPERCLIPAI="2026.325.0"
PINNED_SERVER="2026.325.0"

# Fetch latest
LATEST_COMPANIES_SH=$(npm view companies.sh version 2>/dev/null || echo "unknown")
LATEST_PAPERCLIPAI=$(npm view paperclipai version 2>/dev/null || echo "unknown")
LATEST_SERVER=$(npm view @paperclipai/server version 2>/dev/null || echo "unknown")

check() {
  local name="$1" pinned="$2" latest="$3"
  if [ "$pinned" = "$latest" ]; then
    printf "  %-24s  %s  ✅ up to date\n" "$name" "$pinned"
  else
    printf "  %-24s  %s → %s  ⚠️  UPDATE AVAILABLE\n" "$name" "$pinned" "$latest"
  fi
}

echo "--- Pinned vs. Latest ---"
echo ""
check "companies.sh" "$PINNED_COMPANIES_SH" "$LATEST_COMPANIES_SH"
check "paperclipai" "$PINNED_PAPERCLIPAI" "$LATEST_PAPERCLIPAI"
check "@paperclipai/server" "$PINNED_SERVER" "$LATEST_SERVER"
echo ""

# Check if any are outdated
if [ "$PINNED_COMPANIES_SH" != "$LATEST_COMPANIES_SH" ] || \
   [ "$PINNED_PAPERCLIPAI" != "$LATEST_PAPERCLIPAI" ] || \
   [ "$PINNED_SERVER" != "$LATEST_SERVER" ]; then
  echo "⚠️  Updates available. Before upgrading:"
  echo ""
  echo "  1. Run ./security/static-scan.sh on the new versions"
  echo "  2. Run ./scripts/start.sh --isolated  (Gate 1)"
  echo "  3. Run ./scripts/start.sh --proxy     (Gate 2)"
  echo "  4. Update pinned versions in:"
  echo "       - docker/Dockerfile (ARG lines)"
  echo "       - scripts/check-versions.sh (PINNED_* variables)"
  echo "       - VERSIONS.md (table + integrity hashes)"
  echo "  5. Regenerate reports:"
  echo "       - node security/generate-report.js"
  echo "       - node security/generate-getting-started.js"
  echo "  6. Commit with a reference to the new scan results"
  echo ""
  echo "  Full checklist: docs/UPGRADE-CHECKLIST.md"
else
  echo "All packages match the security-audited versions."
fi

# Check running container if available
echo ""
if docker ps --filter "name=paperclip-sandbox" --format "{{.ID}}" 2>/dev/null | grep -q .; then
  echo "--- Running Container ---"
  echo ""
  CONTAINER_COMPANIES=$(docker exec paperclip-sandbox npx companies.sh --version 2>/dev/null || echo "unknown")
  CONTAINER_PAPERCLIP=$(docker exec paperclip-sandbox npm ls paperclipai --depth=0 2>/dev/null | grep paperclipai | sed 's/.*@//' || echo "unknown")
  echo "  Container companies.sh:  $CONTAINER_COMPANIES"
  echo "  Container paperclipai:   $CONTAINER_PAPERCLIP"

  if [ "$CONTAINER_COMPANIES" != "$PINNED_COMPANIES_SH" ] || [ "$CONTAINER_PAPERCLIP" != "$PINNED_PAPERCLIPAI" ]; then
    echo ""
    echo "  ⚠️  Container versions DO NOT match pinned versions!"
    echo "  Rebuild: ./scripts/stop.sh && ./scripts/start.sh"
  else
    echo "  ✅ Container matches pinned versions."
  fi
fi

echo ""
echo "=== Check Complete ==="
