FROM node:22-slim

# System deps for embedded-postgres and sharp
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash curl libicu-dev libstdc++6 \
  && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd --system paperclip && useradd --system -g paperclip --create-home paperclip

# Working directory
WORKDIR /app
RUN chown paperclip:paperclip /app

# Data directory (bind-mounted from host)
RUN mkdir -p /data && chown paperclip:paperclip /data

# Fake 'open' command — prints URLs instead of opening a browser
COPY --chmod=755 open-stub.sh /usr/local/bin/open
COPY --chmod=755 open-stub.sh /usr/local/bin/xdg-open

USER paperclip

# ============================================================================
# PINNED VERSIONS — Security audited on 2026-03-29
# Do NOT change these without re-running trust gates (see docs/UPGRADE-CHECKLIST.md)
# See VERSIONS.md for integrity hashes and upgrade policy.
# ============================================================================
ARG COMPANIES_SH_VERSION=2026.325.2
ARG PAPERCLIPAI_VERSION=2026.325.0

# Install exact audited versions only
RUN npm install --no-save \
  "companies.sh@${COMPANIES_SH_VERSION}" \
  "paperclipai@${PAPERCLIPAI_VERSION}" \
  "@anthropic-ai/claude-code" \
  && echo "=== Installed versions ===" \
  && npx companies.sh --version 2>/dev/null || true \
  && npm ls paperclipai 2>/dev/null || true \
  && echo "=========================="

# Disable telemetry by default
ENV DO_NOT_TRACK=1
ENV PAPERCLIP_HOME=/data
ENV PAPERCLIP_PORT=3100

COPY --chown=paperclip:paperclip entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 3100

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -sf http://localhost:3100/api/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
