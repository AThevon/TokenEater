#!/bin/bash
#
# Wrapper so the contract checker runs correctly under launchd, which starts
# with a bare environment. It puts Homebrew on PATH (for `gh`) and compiles the
# checker via `xcrun swift`, which is always present with the Xcode toolchain.
#
# Pass through any flag the checker understands: --dry-run, --update-baseline,
# --print. With no flag it fetches, compares, and opens/comments an issue on
# drift.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec /usr/bin/xcrun swift "$SCRIPT_DIR/contract-check.swift" "$@"
