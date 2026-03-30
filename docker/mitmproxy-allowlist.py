"""
mitmproxy addon: block all traffic except allowlisted hosts.

Reads allowed hosts from /config/allowed-hosts.txt (mounted into the container).
Any request to a non-allowlisted host gets a 403 response and is logged.
"""

import logging
from pathlib import Path

from mitmproxy import http, ctx

ALLOWLIST_PATH = "/config/allowed-hosts.txt"

logger = logging.getLogger("allowlist")


def load_allowlist(path: str) -> set[str]:
    hosts = set()
    try:
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                hosts.add(line.lower())
    except FileNotFoundError:
        logger.error("Allowlist file not found: %s — blocking ALL traffic", path)
    return hosts


class AllowlistAddon:
    def __init__(self):
        self.allowed: set[str] = set()

    def load(self, loader):
        self.allowed = load_allowlist(ALLOWLIST_PATH)
        ctx.log.info(f"Allowlist loaded: {len(self.allowed)} hosts — {', '.join(sorted(self.allowed))}")

    def request(self, flow: http.HTTPFlow) -> None:
        host = flow.request.pretty_host.lower()
        if host not in self.allowed:
            ctx.log.warn(f"BLOCKED: {flow.request.method} {flow.request.pretty_url} (host {host} not in allowlist)")
            flow.response = http.Response.make(
                403,
                f"Blocked by allowlist: {host} is not permitted.\n"
                f"To allow this host, add it to config/allowed-hosts.txt and restart.\n",
                {"Content-Type": "text/plain"},
            )


addons = [AllowlistAddon()]
