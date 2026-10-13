#!/usr/bin/env python3
"""Daily watchdog for the local contract checker.

The checker runs on the maintainer's Mac, so nothing on GitHub would notice if
it stopped: the Mac off for weeks, launchd job gone, Claude Code login expired,
`gh` logged out. Every run that reaches GitHub writes the
CONTRACT_CHECK_HEARTBEAT repository variable. This script reads it (passed in
as $HEARTBEAT by .github/workflows/contract-heartbeat.yml) and keeps one issue
labelled `contract-check-down` open while the last successful Claude check is
older than MAX_AGE_DAYS, or while the last run reported an error, closing it
once a fresh check lands.

No dependencies beyond the standard library and an authenticated `gh`
($GH_TOKEN and $GH_REPO).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

MAX_AGE_DAYS = 9
LABEL = "contract-check-down"
TITLE = "The usage API contract check has stopped reporting"


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"gh {' '.join(args[:2])} failed: {result.stderr.strip()}")
    return result.stdout


def parse_date(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def diagnose(raw: str, now: datetime) -> tuple[str | None, dict | None]:
    """Returns (problem, heartbeat). problem is None when all is well."""
    try:
        heartbeat = json.loads(raw) if raw.strip() else None
    except ValueError:
        heartbeat = None
    if not isinstance(heartbeat, dict):
        return ("The `CONTRACT_CHECK_HEARTBEAT` variable is missing or unreadable: the local job has never "
                "reported, or it was uninstalled.", None)
    statuses = heartbeat.get("status") or {}
    failing = {name: value for name, value in statuses.items() if str(value).startswith("error")}
    if failing:
        listed = ", ".join(f"{name}: `{value}`" for name, value in sorted(failing.items()))
        return (f"The last check failed in a way that needs a look ({listed}). The endpoint or its "
                "response may have changed.", heartbeat)
    last_ok = parse_date((heartbeat.get("lastOk") or {}).get("claude"))
    status = statuses.get("claude", "unknown")
    if last_ok is None:
        return (f"The local job has never completed a Claude check (last status: `{status}`).", heartbeat)
    age = now - last_ok
    if age > timedelta(days=MAX_AGE_DAYS):
        return (f"The last successful Claude check was {age.days} days ago, on {last_ok:%Y-%m-%d} "
                f"(last status: `{status}`).", heartbeat)
    return None, heartbeat


def main() -> int:
    now = datetime.now(timezone.utc)
    problem, heartbeat = diagnose(os.environ.get("HEARTBEAT", ""), now)
    open_issues = json.loads(gh("issue", "list", "--label", LABEL, "--state", "open", "--json", "number"))

    if problem is None:
        for issue in open_issues:
            gh("issue", "close", str(issue["number"]),
               "--comment", "The contract check reported a successful run again. Closing.")
        print("Heartbeat is fresh.")
        return 0

    body = "\n".join([
        problem,
        "",
        "The weekly usage API contract check runs on the maintainer's Mac (`Tools/contract-check`), so while it is "
        "down, a change in the Claude or Codex usage payload goes unnoticed.",
        "",
        "Things to check, most likely first:",
        "",
        "- Claude Code has not been opened recently, so its login token expired (`token-expired`): open it once.",
        "- The job is not loaded: `launchctl print gui/$(id -u)/dev.athevon.tokeneater.contract-check`.",
        "- `gh` lost its login: `gh auth status`.",
        "- The log: `~/Library/Logs/tokeneater-contract-check.log`.",
        "",
        "Last heartbeat:",
        "",
        "```json",
        json.dumps(heartbeat, indent=2, sort_keys=True) if heartbeat else "(none)",
        "```",
        "",
        f"_Checked {now:%Y-%m-%d %H:%M} UTC by `.github/workflows/contract-heartbeat.yml`. "
        "This issue closes itself after the next successful check._",
    ])
    if open_issues:
        gh("issue", "edit", str(open_issues[0]["number"]), "--body", body)
        print(f"Updated issue #{open_issues[0]['number']}.")
    else:
        gh("label", "create", LABEL, "--color", "B60205", "--force",
           "--description", "The local usage API contract check stopped reporting")
        print(gh("issue", "create", "--title", TITLE, "--label", LABEL, "--body", body).strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
