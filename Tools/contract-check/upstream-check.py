#!/usr/bin/env python3
"""Watch the openai/codex files that define the Codex usage payload.

The Codex CLI decodes `GET /backend-api/wham/usage` with models that live in
the public openai/codex repo. When one of them changes, the payload TokenEater
reads has probably changed too, or is about to. This script compares the blob
SHA of each watched file with `upstream/codex.lock.json` and, on a change,
rewrites the lock and writes a PR body: links to the upstream commits, and the
wire names that appeared or disappeared, checked against what TokenEater
decodes (`read-set.json`) and the plans it maps (`CodexPlanType.swift`).

It needs no credential beyond the workflow's own token (for the API rate
limit), and it sees only what the CLI models: a field the CLI ignores never
shows up here. The local checker is what catches those, with a live login.

Run by .github/workflows/contract-upstream.yml. Locally:
    python3 Tools/contract-check/upstream-check.py --body /tmp/body.md
No dependencies beyond the standard library and an authenticated `gh`.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LOCK = HERE / "upstream" / "codex.lock.json"
READ_SET = HERE / "read-set.json"
PLAN_TYPES = ROOT / "Shared" / "Models" / "CodexPlanType.swift"


def gh(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True)


def gh_json(endpoint: str):
    result = gh("api", endpoint)
    if result.returncode != 0:
        sys.exit(f"gh api {endpoint} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def blob_sha(repo: str, path: str, ref: str) -> str | None:
    result = gh("api", f"repos/{repo}/contents/{path}?ref={ref}", "--jq", ".sha")
    if result.returncode != 0:
        if "HTTP 404" in result.stderr:
            return None
        sys.exit(f"could not read {path}: {result.stderr.strip()}")
    return result.stdout.strip()


def raw(repo: str, path: str, ref: str) -> str:
    result = gh("api", "-H", "Accept: application/vnd.github.raw+json",
                f"repos/{repo}/contents/{path}?ref={ref}")
    return result.stdout if result.returncode == 0 else ""


def wire_names(path: str, text: str) -> set[str]:
    """Field names and enum values a file puts on the wire."""
    if not text:
        return set()
    if path.endswith(".json"):
        names: set[str] = set()

        def walk(node):
            if isinstance(node, dict):
                names.update(node.get("properties", {}).keys())
                names.update(v for v in node.get("enum", []) if isinstance(v, str))
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)

        try:
            walk(json.loads(text))
        except ValueError:
            pass
        return names
    renamed = set(re.findall(r'rename\s*=\s*"([^"]+)"', text))
    fields = set(re.findall(r"^\s*pub(?:\(crate\))?\s+(\w+)\s*:", text, re.M))
    return renamed | fields


def plan_types(path: str, text: str) -> set[str]:
    """The PlanType enum, from the Rust payload model or the JSON Schema."""
    if path.endswith(".json"):
        try:
            return set(json.loads(text).get("definitions", {}).get("PlanType", {}).get("enum", []))
        except ValueError:
            return set()
    block = re.search(r"pub enum PlanType\s*\{(.*?)\n\}", text, re.S)
    return set(re.findall(r'rename\s*=\s*"([^"]+)"', block.group(1))) if block else set()


def snake(name: str) -> str:
    """The JSON Schema is camelCase; the wire, and the read set, are snake_case."""
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()


def tokeneater_names() -> tuple[set[str], set[str]]:
    paths = json.loads(READ_SET.read_text())["providers"]["codex-usage"]["paths"]
    decoded = {path.split(".")[-1].replace("[]", "") for path in paths}
    mapped = set()
    for line in PLAN_TYPES.read_text().splitlines():
        if line.strip().startswith('case "'):
            mapped.update(re.findall(r'"([a-z0-9_]+)"', line))
    return decoded, mapped


def commits_since(repo: str, path: str, head: str, since: str) -> list[str]:
    commits = gh_json(f"repos/{repo}/commits?path={path}&sha={head}&since={since}&per_page=20")
    lines = []
    for commit in commits:
        title = commit["commit"]["message"].splitlines()[0]
        lines.append(f"  - [`{commit['sha'][:9]}`]({commit['html_url']}) {title}")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--body", required=True, help="where to write the PR body")
    parser.add_argument("--output", help="a $GITHUB_OUTPUT file to append changed=/missing= to")
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text())
    repo, old = lock["repo"], lock["commit"]
    head = gh_json(f"repos/{repo}/commits/main")["sha"]

    current = {path: blob_sha(repo, path, head) for path in lock["files"]}
    changed = [path for path, sha in current.items() if sha != lock["files"][path]]
    missing = [path for path in changed if current[path] is None]

    def output(**values: bool) -> None:
        if args.output:
            with open(args.output, "a") as handle:
                for key, value in values.items():
                    handle.write(f"{key}={'true' if value else 'false'}\n")

    if not changed:
        print(f"No watched file changed since {old[:9]}.")
        output(changed=False, missing=False)
        return 0

    decoded, mapped = tokeneater_names()
    since = gh_json(f"repos/{repo}/commits/{old}")["commit"]["committer"]["date"]
    lines = [
        f"The openai/codex files that define the Codex usage payload changed since the last acknowledged commit "
        f"([`{old[:9]}...{head[:9]}`](https://github.com/{repo}/compare/{old}...{head})). "
        "The CLI changes its models when the backend payload changes, so TokenEater's decoder may need to follow.",
        "",
        "### Changed files",
        "",
    ]
    impact: list[str] = []
    for path in changed:
        name = path.split("/")[-1]
        if current[path] is None:
            lines.append(f"- `{path}`: **no longer exists**. Find where it moved and update the lock by hand.")
            continue
        lines.append(f"- [`{name}`](https://github.com/{repo}/commits/{head}/{path})")
        lines += commits_since(repo, path, head, since)

        before, after = raw(repo, path, old), raw(repo, path, head)
        added = sorted(wire_names(path, after) - wire_names(path, before))
        removed = sorted(wire_names(path, before) - wire_names(path, after))
        plans = plan_types(path, after)
        for item in added:
            if item in plans:
                note = "`CodexPlanType` maps it." if item in mapped else \
                    "`CodexPlanType` does not map it, so it shows as a raw badge."
                impact.append(f"- `{item}`: new plan type in `{name}`. {note}")
            else:
                note = f"TokenEater already decodes `{snake(item)}`." if snake(item) in decoded else \
                    "TokenEater does not decode it."
                impact.append(f"- `{item}`: new in `{name}`. {note}")
        for item in removed:
            note = " TokenEater reads it: check the live payload." if snake(item) in decoded else ""
            impact.append(f"- `{item}`: gone from `{name}`.{note}")

    lines += ["", "### TokenEater impact", ""]
    lines += impact or ["- No wire name was added or removed: likely a docs, defaults or refactor change. "
                        "Skim the commits above, then merge to acknowledge."]
    lines += [
        "",
        "Merging this PR moves `Tools/contract-check/upstream/codex.lock.json` forward. "
        "Fix `Shared/Models/CodexUsageModels.swift` or `CodexPlanType.swift` first if the impact calls for it.",
        "",
        "_Opened by `.github/workflows/contract-upstream.yml`._",
    ]
    Path(args.body).write_text("\n".join(lines) + "\n")

    lock["commit"] = head
    lock["files"] = current
    LOCK.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")

    print(f"{len(changed)} watched file(s) changed, {len(missing)} missing.")
    output(changed=True, missing=bool(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
