#!/usr/bin/env python3
"""Verify that AGENTS.md still describes the tree it ships with.

AGENTS.md is what every AI coding agent reads before touching this repo, so a
stale claim in it actively causes bad work: a path that resolves to nothing, an
inventory that omits half a directory, a "load-bearing" step that is a no-op.
This script fails CI when the document and the code disagree.

It is deliberately a checker, not a generator. A script that rewrote AGENTS.md
would silently paper over real regressions (a deleted protocol, a dropped mock)
by updating the prose to match. Failing the build puts a human in the loop.

Run it locally with:  python3 scripts/check-docs.py
No dependencies. Exit code 0 means the doc matches the tree.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "AGENTS.md"

# Services that legitimately break the "one protocol, one mock" convention.
# Adding an entry here is a deliberate act: AGENTS.md documents these two by
# name, so if you add a third, say so there too.
SERVICE_PROTOCOL_EXCEPTIONS = {
    "LegacyHelperCleanupService",
    # A composer over other services, not an I/O seam of its own.
    "CombinedSessionHistoryService",
}
SERVICE_MOCK_EXCEPTIONS = {
    "LegacyHelperCleanupService",
    "SessionHistoryService",
    "CombinedSessionHistoryService",
}

PATH_EXTENSIONS = (".swift", ".md", ".yml", ".yaml", ".json", ".sh", ".txt",
                   ".plist", ".applescript", ".xml", ".py")

# The feature index quotes paths relative to a target root on purpose
# ("Helpers/SmartColor.swift"), so a token counts as resolved if it exists
# under the repo root or under any of these.
PATH_ROOTS = ("", "Shared", "TokenEaterApp", "TokenEaterWidget", "TokenEaterTests",
              "Shared/Services", "docs")

failures: list[str] = []
notes: list[str] = []


def fail(check: str, message: str) -> None:
    failures.append(f"{check}: {message}")


def ok(check: str, message: str) -> None:
    notes.append(f"{check}: {message}")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def backticked(text: str) -> list[str]:
    return re.findall(r"`([^`\n]+)`", text)


# --------------------------------------------------------------------------
# 1. The version in the doc matches project.yml
# --------------------------------------------------------------------------
def check_version(doc: str) -> None:
    m = re.search(r"^Current version: (\S+) ", doc, re.M)
    if not m:
        fail("version", "no 'Current version: X' line found in AGENTS.md")
        return
    documented = m.group(1)
    project = read(ROOT / "project.yml")
    pm = re.search(r"MARKETING_VERSION:\s*[\"']?([0-9][^\s\"']*)", project)
    if not pm:
        fail("version", "MARKETING_VERSION not found in project.yml")
        return
    if documented != pm.group(1):
        fail("version", f"AGENTS.md says {documented}, project.yml says {pm.group(1)}")
    else:
        ok("version", documented)


# --------------------------------------------------------------------------
# 2. Every repo path mentioned in the doc resolves
# --------------------------------------------------------------------------
def check_paths(doc: str) -> None:
    bad = []
    checked = 0
    for token in backticked(doc):
        token = token.strip()
        if "/" not in token:
            continue
        # Skip absolute paths, home paths, globs, shell expansions, URLs,
        # generated projects and build output.
        if token.startswith(("~", "/", "http", "$", "@")):
            continue
        if any(c in token for c in "*$ "):
            continue
        if token.startswith("build/") or ".xcodeproj" in token:
            continue
        # Runtime locations under the user's Library, not repo files.
        if token.startswith("com."):
            continue
        if not token.endswith(PATH_EXTENSIONS) and not token.endswith("/"):
            continue
        checked += 1
        if not any((ROOT / prefix / token).exists() for prefix in PATH_ROOTS):
            bad.append(token)
    for token in bad:
        fail("paths", f"`{token}` does not exist")
    if not bad:
        ok("paths", f"{checked} referenced paths all resolve")


# --------------------------------------------------------------------------
# 3. The store inventory lists every store, and only real ones
# --------------------------------------------------------------------------
def check_stores(doc: str) -> None:
    m = re.search(r"^- `Shared/Stores/` - (.+)$", doc, re.M)
    if not m:
        fail("stores", "no `Shared/Stores/` inventory line found")
        return
    documented = set(re.findall(r"\b(\w+Store)\b", m.group(1)))
    on_disk = {p.stem for p in (ROOT / "Shared/Stores").glob("*.swift")}
    for missing in sorted(on_disk - documented):
        fail("stores", f"{missing} exists but the inventory line omits it")
    for ghost in sorted(documented - on_disk):
        fail("stores", f"the inventory line names {ghost}, which has no file")
    if on_disk == documented:
        ok("stores", f"{len(on_disk)} stores, all listed")


# --------------------------------------------------------------------------
# 4. The helper inventory lists every helper, and only real ones
# --------------------------------------------------------------------------
def check_helpers(doc: str) -> None:
    m = re.search(r"^- `Shared/Helpers/` - (.+)$", doc, re.M)
    if not m:
        fail("helpers", "no `Shared/Helpers/` inventory line found")
        return
    line = m.group(1)
    on_disk = {p.stem for p in (ROOT / "Shared/Helpers").glob("*.swift")}
    # Every capitalised word on the line is a claim about a file. Filtering
    # this set down to what exists on disk, as it used to, made the ghost
    # direction unfalsifiable: a helper deleted from the tree but left in the
    # prose passed, which is exactly the rot this script exists to catch.
    named = set(re.findall(r"\b([A-Z]\w+)\b", line))
    # Prose capitals that are not file claims.
    NOT_FILES = {"Check", "Four", "UserDefaults", "WidgetCenter", "I", "O"}
    documented = named - NOT_FILES
    for missing in sorted(on_disk - documented):
        fail("helpers", f"{missing} exists but the inventory line omits it")
    for ghost in sorted(documented - on_disk):
        fail("helpers", f"the inventory line names {ghost}, which does not exist")
    if on_disk == documented:
        ok("helpers", f"{len(on_disk)} helpers, all listed")


# --------------------------------------------------------------------------
# 5. The one-protocol-one-mock convention the doc states still holds
# --------------------------------------------------------------------------
def check_service_convention() -> None:
    services = {p.stem for p in (ROOT / "Shared/Services").glob("*.swift")}
    protocols = {p.stem for p in (ROOT / "Shared/Services/Protocols").glob("*.swift")}
    mocks = {p.stem for p in (ROOT / "TokenEaterTests/Mocks").glob("*.swift")}

    for service in sorted(services):
        if service not in SERVICE_PROTOCOL_EXCEPTIONS and f"{service}Protocol" not in protocols:
            fail("services", f"{service} has no {service}Protocol; add one or document "
                             f"the exception in AGENTS.md and in this script")
        if service not in SERVICE_MOCK_EXCEPTIONS and f"Mock{service}" not in mocks:
            fail("services", f"{service} has no Mock{service}; add one or document "
                             f"the exception in AGENTS.md and in this script")

    # An exception that stopped being one means the doc now overstates the gaps.
    for service in sorted(SERVICE_PROTOCOL_EXCEPTIONS):
        if f"{service}Protocol" in protocols:
            fail("services", f"{service} now HAS a protocol; drop it from the exception "
                             f"list here and from AGENTS.md")
    for service in sorted(SERVICE_MOCK_EXCEPTIONS):
        if f"Mock{service}" in mocks:
            fail("services", f"{service} now HAS a mock; drop it from the exception "
                             f"list here and from AGENTS.md")
    if not failures:
        ok("services", f"{len(services)} services follow the protocol/mock convention")


# --------------------------------------------------------------------------
# 6. The widget row lists exactly the widgets in the bundle
# --------------------------------------------------------------------------
def check_widgets(doc: str) -> None:
    source = read(ROOT / "TokenEaterWidget/TokenEaterWidget.swift")
    body = re.search(r"struct \w+Bundle: WidgetBundle \{.*?var body: some Widget \{(.*?)\n    \}",
                     source, re.S)
    if not body:
        fail("widgets", "could not locate the WidgetBundle body")
        return
    declared = set(re.findall(r"^\s*(\w+)\(\)\s*$", body.group(1), re.M))
    row = re.search(r"^\| Widget \| (.+)$", doc, re.M)
    if not row:
        fail("widgets", "no Widget row found in the feature index")
        return
    # Only the parenthesised bundle list counts. Scanning the whole row made
    # any prose containing the word "Widget" look like a declared widget.
    listed = re.search(r"`WidgetBundle`:\s*([^)]*)\)", row.group(1))
    if not listed:
        fail("widgets", "the Widget row no longer spells out the `WidgetBundle`: list")
        return
    documented = set(re.findall(r"\b(\w*Widget)\b", listed.group(1)))
    for missing in sorted(declared - documented):
        fail("widgets", f"{missing} is in the bundle but not in the Widget row")
    ghosts = {n for n in documented - declared if n not in {"TokenEaterWidget"}}
    for ghost in sorted(ghosts):
        fail("widgets", f"the Widget row names {ghost}, which the bundle does not declare")
    if not (declared - documented) and not ghosts:
        ok("widgets", f"{len(declared)} widgets, all listed")


# --------------------------------------------------------------------------
# 7. The hard SwiftUI rules are enforced, not just written down
# --------------------------------------------------------------------------
def grep(pattern: str, *paths: str) -> list[str]:
    """grep, but a grep that could not run is an error rather than zero hits.

    Exit 1 means no matches; anything else (2 = a path that does not exist)
    used to come back as an empty list, so renaming a source directory would
    have silently disabled the `@Observable` ban and the binding audit while
    this script kept printing ok.
    """
    # The return code is not enough on its own: with `--include`, the grep on
    # PATH here exits 1 on a directory that does not exist, which is
    # indistinguishable from "searched it, found nothing". So the paths are
    # checked first. Without this, renaming a source directory would silently
    # turn the `@Observable` ban and the binding audit into no-ops while this
    # script kept printing ok, which is worse than not having them.
    for path in paths:
        if not (ROOT / path).exists():
            fail("grep", f"{path} does not exist, so nothing in it was checked")
            return []
    cmd = ["grep", "-rnE", "--include=*.swift", pattern, *paths]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if out.returncode not in (0, 1):
        fail("grep", f"could not search {' '.join(paths)}: {out.stderr.strip() or 'exit ' + str(out.returncode)}")
    return [line for line in out.stdout.splitlines() if line.strip()]


def check_swiftui_rules() -> None:
    targets = ["Shared", "TokenEaterApp", "TokenEaterWidget"]

    observable = [h for h in grep(r"^\s*@Observable", *targets)]
    for hit in observable:
        fail("swiftui", f"@Observable is banned (100% CPU freeze in Release): {hit}")

    app_file = ROOT / "TokenEaterApp/App/TokenEaterApp.swift"
    if not app_file.exists():
        fail("swiftui", "TokenEaterApp/App/TokenEaterApp.swift not found; "
                        "update this check and the doc's 'where to start reading' list")
    elif "@StateObject" in read(app_file):
        fail("swiftui", "@StateObject in the App struct is banned; use `private let`")

    if not observable and app_file.exists():
        ok("swiftui", "no @Observable, no @StateObject in the App struct")

    # The doc enumerates the hand-rolled bindings that survive on purpose.
    # Compare file sets rather than a count, so the check never needs a number.
    # The leading class excludes false positives like "onToggleReset: {".
    hits = grep(r"(^|[^A-Za-z])set: \{", *targets)
    found = {Path(line.split(":", 1)[0]).name for line in hits}
    doc = read(DOC)
    para = re.search(r"- \*\*No `\$store\.computedProp` bindings\.\*\*(.+)", doc)
    if not para:
        fail("swiftui", "could not find the computed-binding rule paragraph")
    else:
        listed = {Path(tok).name for tok in backticked(para.group(1))
                  if tok.endswith(".swift")}
        for missing in sorted(found - listed):
            fail("swiftui", f"{missing} hand-rolls a Binding but the rule paragraph "
                            f"does not account for it")
        for ghost in sorted(listed - found):
            fail("swiftui", f"the rule paragraph names {ghost} as hand-rolling a "
                            f"Binding, but it no longer does; drop it")
        if found == listed:
            ok("swiftui", f"{len(found)} documented hand-rolled bindings, no others")


# --------------------------------------------------------------------------
# 8. No machine-specific cache prefix, anywhere in the docs or scripts
# --------------------------------------------------------------------------
def check_cache_paths() -> None:
    # /private/var/folders/<two chars>/ is a per-user hash. Hardcoding it makes
    # the widget-cache nuke a silent no-op on every other machine, which is
    # exactly the bug this check exists to prevent coming back.
    out = subprocess.run(
        ["grep", "-rn", "-E", r"/(private/)?var/folders/[a-z0-9]{2}/",
         "--include=*.md", "--include=*.sh", "--include=*.yml", "--include=*.py",
         "."],
        cwd=ROOT, capture_output=True, text=True)
    hits = [l for l in out.stdout.splitlines() if "/build/" not in l and l.strip()]
    for hit in hits:
        fail("cache-paths", f"hardcoded per-user cache prefix, use getconf "
                            f"DARWIN_USER_CACHE_DIR instead: {hit}")
    if not hits:
        ok("cache-paths", "no hardcoded per-user cache prefixes")


# --------------------------------------------------------------------------
# 9. No bare inventory counts, which is how this document rotted last time
# --------------------------------------------------------------------------
def check_no_magic_counts(doc: str) -> None:
    patterns = [
        (r"roughly \d+ `@Test`", "a hardcoded test count; keep the recompute command instead"),
        (r"\b\d+ services\b", "a hardcoded service count; state the convention instead"),
        (r"\b\d+ `ObservableObject` state containers", "a hardcoded store count; enumerate them instead"),
        (r"### The \d+ stores", "a count in the stores heading"),
        (r"\b\d+ (?:pure )?enums/structs", "a hardcoded helper count; enumerate them instead"),
        (r"\b\d+ reusable SwiftUI views", "a hardcoded component count"),
    ]
    for pattern, why in patterns:
        m = re.search(pattern, doc)
        if m:
            fail("magic-counts", f"{why} (found \"{m.group(0)}\")")
    if not any(re.search(p, doc) for p, _ in patterns):
        ok("magic-counts", "no bare inventory counts reintroduced")


def main() -> int:
    if not DOC.exists():
        print("AGENTS.md not found", file=sys.stderr)
        return 1
    doc = read(DOC)

    check_version(doc)
    check_paths(doc)
    check_stores(doc)
    check_helpers(doc)
    check_service_convention()
    check_widgets(doc)
    check_swiftui_rules()
    check_cache_paths()
    check_no_magic_counts(doc)

    for note in notes:
        print(f"  ok    {note}")
    for failure in failures:
        print(f"  FAIL  {failure}")

    if failures:
        print(f"\n{len(failures)} problem(s). AGENTS.md and the tree disagree: fix "
              f"whichever one is wrong.")
        return 1
    print("\nAGENTS.md matches the tree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
