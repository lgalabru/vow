#!/usr/bin/env python3
"""Verify Vow's HTTPS association before enabling the native Apple key flow."""
import argparse
import json
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError(f"Duplicate JSON key: {name}")
        result[name] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("domain", help="Controlled HTTPS hostname, without a URL path")
    parser.add_argument("--app-id", default="4HY7TSGF6M.org.vow.prototype")
    parser.add_argument("--enable", action="store_true", help="Write the verified domain to the Apple build config")
    args = parser.parse_args()
    domain = args.domain.lower()
    labels = domain.split(".")
    if len(domain) > 253 or len(labels) < 2 or not all(
        re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) for label in labels
    ) or labels[-1] in {"invalid", "test", "example", "local", "localhost"}:
        parser.error("Use a public HTTPS hostname you control, such as vow.your-domain.com.")
    if not re.fullmatch(r"[A-Z0-9]{10}\.[A-Za-z0-9.-]+", args.app_id):
        parser.error("App ID must be TEAMID.bundle.identifier.")
    url = f"https://{domain}/.well-known/apple-app-site-association"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
            if response.status != 200 or response.headers.get_content_type() != "application/json":
                raise ValueError("Serve the association file as HTTP 200, application/json, without redirects.")
            data = response.read(131073)
            if len(data) > 131072:
                raise ValueError("Association file exceeds this checker's 128 KB limit.")
        document = json.loads(data, object_pairs_hook=unique_object)
        apps = document.get("webcredentials", {}).get("apps", [])
        if not isinstance(apps, list) or not all(isinstance(value, str) for value in apps) or args.app_id not in apps:
            raise ValueError(f"webcredentials.apps does not include {args.app_id}.")
    except (urllib.error.URLError, ValueError, TypeError, AttributeError) as error:
        print(f"Association verification failed: {error}", file=sys.stderr)
        return 1
    print(f"Verified {url} for {args.app_id}.")
    if args.enable:
        root = Path(__file__).resolve().parents[1]
        config = root / "apps/apple/Config/NativeSecurityKey.xcconfig"
        temporary = config.with_suffix(".xcconfig.tmp")
        temporary.write_text(
            "// Verified HTTPS association. Keep this RP stable after enrollment.\n"
            f"VOW_WEBAUTHN_RP_ID = {domain}\n"
            "VOW_IPAD_ENTITLEMENTS = Config/Vow-iPad-NativeSecurityKey.entitlements\n"
        )
        temporary.replace(config)
        print("Enabled native security-key signing for the next signed build. Apple association caching and offline behavior still need device testing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
