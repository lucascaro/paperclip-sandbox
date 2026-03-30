"""
mitmproxy addon: block all traffic except allowlisted hosts and URLs.

Reads allowed entries from /config/allowed-hosts.txt (mounted into the container).
Supports:
  - Host-only:    api.anthropic.com           (all methods, all paths)
  - Exact URL:    GET https://example.com/path (method + scheme + host + path must match)

Any request not matching the allowlist gets a 403 response and is logged.
"""

import logging
from pathlib import Path
from urllib.parse import urlparse, urlunparse

from mitmproxy import http, ctx

ALLOWLIST_PATH = "/config/allowed-hosts.txt"

logger = logging.getLogger("allowlist")


def load_allowlist(path: str) -> tuple[set[str], list[tuple[str, str]]]:
    """Returns (host_set, url_rules) where url_rules are (METHOD, URL) tuples."""
    hosts = set()
    url_rules = []
    try:
        for line in Path(path).read_text().splitlines():
            line = line.split("#")[0].strip()
            if not line:
                continue
            # URL rule: "GET https://example.com/path"
            if " " in line and line.split()[0].isupper():
                parts = line.split(None, 1)
                method = parts[0].upper()
                raw_url = parts[1]
                # Normalize scheme + host to lowercase but preserve path case
                parsed = urlparse(raw_url)
                normalized = urlunparse((
                    parsed.scheme.lower(),
                    parsed.netloc.lower(),
                    parsed.path,
                    parsed.params,
                    parsed.query,
                    parsed.fragment,
                ))
                url_rules.append((method, normalized))
            else:
                hosts.add(line.lower())
    except FileNotFoundError:
        logger.error("Allowlist file not found: %s — blocking ALL traffic", path)
    return hosts, url_rules


class AllowlistAddon:
    def __init__(self):
        self.allowed_hosts: set[str] = set()
        self.url_rules: list[tuple[str, str]] = []

    def load(self, loader):
        self.allowed_hosts, self.url_rules = load_allowlist(ALLOWLIST_PATH)
        entries = sorted(self.allowed_hosts) + [f"{m} {u}" for m, u in self.url_rules]
        ctx.log.info(f"Allowlist loaded: {len(entries)} rules — {', '.join(entries)}")

    def request(self, flow: http.HTTPFlow) -> None:
        host = flow.request.pretty_host.lower()

        # Check host-level allow
        if host in self.allowed_hosts:
            return

        # Check URL-level rules
        method = flow.request.method.upper()
        parsed = urlparse(flow.request.pretty_url)
        url = urlunparse((
            parsed.scheme.lower(),
            parsed.netloc.lower(),
            parsed.path,
            parsed.params,
            parsed.query,
            parsed.fragment,
        ))
        for rule_method, rule_url in self.url_rules:
            if method == rule_method and url == rule_url:
                return

        ctx.log.warn(f"BLOCKED: {flow.request.method} {flow.request.pretty_url} (not in allowlist)")
        flow.response = http.Response.make(
            403,
            f"Blocked by allowlist: {flow.request.method} {flow.request.pretty_url} is not permitted.\n"
            f"To allow this request, either add host '{host}' or an exact rule "
            f"'{flow.request.method} {flow.request.pretty_url}' to config/allowed-hosts.txt and restart.\n",
            {"Content-Type": "text/plain"},
        )


addons = [AllowlistAddon()]
