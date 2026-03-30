# Paperclip Architecture Reference

How the paperclipai platform works internally. Reference for safe operation.

## System Overview

Paperclip is a three-layer system:

1. **companies.sh** — thin CLI that fetches company templates from GitHub
2. **paperclipai** — Node.js server with embedded PostgreSQL, serves on port 3100
3. **@paperclipai/server** — open-source runtime (MIT license, TypeScript source at github.com/paperclipai/paperclip/tree/master/server/src) that executes agents

## Data Layout

All data roots at `PAPERCLIP_HOME` (we set this to `/data` inside Docker,
which bind-mounts to `./data/` on the host).

```
data/                                    # = PAPERCLIP_HOME
  instances/
    default/                             # PAPERCLIP_INSTANCE_ID
      config.json                        # Server configuration
      db/                                # Embedded PostgreSQL data files
      logs/                              # Server logs
      secrets/
        master.key                       # Local encryption key
      data/
        storage/                         # File uploads, attachments
        backups/                         # Auto-backups (hourly, 30-day retention)
      workspaces/
        <agent-id>/                      # Per-agent working directory ($AGENT_HOME)
      companies/
        <company-id>/
          codex-home/                    # Codex adapter home
      projects/                          # Project checkouts
```

## Server

- **Runtime**: Node.js 20+
- **Database**: Embedded PostgreSQL (auto-starts, finds available port from 5432)
- **UI**: React dashboard at http://localhost:3100
- **Health**: `GET /api/health` returns `{"status":"ok"}`
- **Companies**: `GET /api/companies` lists all companies

## Company Model

- Multiple companies coexist on one server with data isolation
- Each company has its own org chart, budget, agents, and task queues
- Agent workspaces are scoped per-agent under `workspaces/<agent-id>/`
- Companies are created via the dashboard UI or `companies.sh add`

## Agent Model

Agents are LLM-powered workers that execute through "heartbeats" — scheduled
activation cycles where they wake, check for work, and execute.

**Hierarchy**: Board (humans) > CEO agent > Department agents > Workers

**Adapters**: Claude Code, OpenAI Codex, Gemini, Cursor, Bash scripts, HTTP endpoints

**Lifecycle**: Hire > Strategy proposal (Board approval) > Task execution > Delegation

## Key Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PAPERCLIP_HOME` | `~/.paperclip` | Root data directory (we override to `/data`) |
| `PAPERCLIP_INSTANCE_ID` | `default` | Scopes all data under instances/ |
| `PAPERCLIP_PORT` | `3100` | Server port |
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` | Security model |
| `DATABASE_URL` | (embedded) | External PostgreSQL URL |
| `DO_NOT_TRACK` | `0` | Disable telemetry when set to `1` |

## Telemetry

By default, paperclipai:
- Writes a UUID to `~/.config/companies.sh/telemetry.json`
- POSTs to `rusqrrg391.execute-api.us-east-1.amazonaws.com/ingest`

We disable this with `DO_NOT_TRACK=1` in all configurations.
