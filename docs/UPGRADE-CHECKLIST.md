# Upgrade Checklist

Follow this checklist before upgrading paperclipai or companies.sh to a new version.
Or run `./scripts/upgrade.sh` for a guided interactive flow.

## Before Upgrading

- [ ] Check for updates: `./scripts/check-versions.sh`
- [ ] Back up current data: `./scripts/backup.sh`
- [ ] Note current pinned versions from `VERSIONS.md`
- [ ] Stop the sandbox: `./scripts/stop.sh`

## Re-Run Trust Gates

- [ ] **Gate 0**: Run `./security/static-scan.sh` on the new version
  - Compare output against previous scan results
  - Flag any new patterns: new endpoints, new env var access, new file writes
- [ ] **Gate 1**: Start with `./scripts/start.sh` (default: proxy-based allowlist)
  - Verify only allowlisted hosts are reachable, check startup isolation self-check passes
  - Inspect all traffic at http://localhost:8081 (password: `p`)
  - Compare against previous traffic patterns
  - Flag any new outbound destinations or blocked requests

## Apply Upgrade

- [ ] Update pinned versions in `docker/Dockerfile` (ARG lines)
- [ ] Update pinned versions in `scripts/check-versions.sh` (PINNED_* variables)
- [ ] Rebuild: `docker compose -f docker/docker-compose.yml build --no-cache`
- [ ] Start normally: `./scripts/start.sh`
- [ ] Run `./security/audit-run.sh` after 10 minutes of operation
- [ ] Check API key spend on provider dashboards
- [ ] Monitor with `./scripts/monitor.sh` for 15 minutes

## After Upgrading

- [ ] Update `VERSIONS.md` with:
  - New version numbers
  - New integrity hashes (`npm view <pkg>@<version> dist.integrity`)
  - Today's date as analysis date
- [ ] Regenerate reports:
  - `node security/generate-report.js`
  - `node security/generate-getting-started.js`
- [ ] Commit all changes with a reference to the new scan results
- [ ] Note any new environment variables or configuration changes
