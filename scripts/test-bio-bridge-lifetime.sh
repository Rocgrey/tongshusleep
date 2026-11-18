#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bio-bridge-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

# The header is required; no proprietary object code is linked into this host test.
xcrun --sdk macosx clang++ -std=c++17 -fobjc-arc -framework Foundation \
  -fsanitize=address -g "$repo_dir/scripts/tests/bio-bridge-lifetime.mm" -o "$test_dir/lifetime"
"$test_dir/lifetime"

# A project that silently disables ARC must fail at build time, not on login.
if xcrun --sdk macosx clang++ -std=c++17 -fno-objc-arc -fsyntax-only \
  "$repo_dir/scripts/tests/bio-bridge-lifetime.mm" > "$test_dir/no-arc.log" 2>&1; then
  echo "error: bridge unexpectedly compiled without ARC" >&2
  exit 1
fi
grep -q 'BIOLocalSleepBridge requires ARC' "$test_dir/no-arc.log"
echo "BIO bridge build guard: non-ARC compilation rejected."
