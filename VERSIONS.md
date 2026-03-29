# Pinned Versions — Security Audited

These are the exact package versions that have been security-analyzed.
**Do not upgrade without re-running the trust gates** (see docs/UPGRADE-CHECKLIST.md).

## Analyzed Packages

| Package | Version | Published | Integrity (SHA-512) |
|---------|---------|-----------|---------------------|
| `companies.sh` | `2026.325.2` | 2026-03-25 | `sha512-5YE4kdjMtGJM6iirdUKp69y2wo0bGErTEezy47HAsufORa2ZGyGR4v+HANgegrYUS8MbH/zUFMibwAO5fl675Q==` |
| `paperclipai` | `2026.325.0` | 2026-03-25 | `sha512-95icEkRwUygFXIKVqeRPDGfM7a5FMkXUxiZyGNIcFbx01YQkLzbAOaGxn6R3AKrezWlOmLYQSy5SZAXEgbsfgg==` |
| `@paperclipai/server` | `2026.325.0` | 2026-03-25 | `sha512-gkR4Hfrdr4muzmHx0D7aIgQB3THMG7CBwUvFbrQePW0gn35Lp+0oXok7zMF6dqsjHGtl0GZ81NooYqQr26FTMg==` |

## Analysis Date

**2026-03-29** — Static scan completed. See `security/PLAYBOOK.md` for findings.

## How to Verify

After `npm install` inside the container, verify the installed versions match:

```bash
docker exec paperclip-sandbox npx companies.sh --version
docker exec paperclip-sandbox npm ls paperclipai
docker exec paperclip-sandbox npm ls @paperclipai/server
```

Or verify integrity hashes directly:

```bash
npm pack companies.sh@2026.325.2 --dry-run 2>&1 | grep integrity
npm pack paperclipai@2026.325.0 --dry-run 2>&1 | grep integrity
```

## Upgrade Policy

1. Check for new versions: `npm outdated companies.sh paperclipai`
2. Before upgrading, re-run **Gates 0–2** from `security/PLAYBOOK.md`
3. Update this file with new versions, integrity hashes, and analysis date
4. Regenerate the security report: `node security/generate-report.js`
5. Commit the version bump with a reference to the new scan results
