#!/usr/bin/env bash
#
# Tests for scripts/resolve-version.sh. Needs network access to the npm registry, jq and npx.
# CI runs it on several Node.js versions: the resolved version must never depend on the runner.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
RESOLVE=scripts/resolve-version.sh
failed=0

ok() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1${2:+ ($2)}"; failed=$((failed + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected '$2', got '$3'"; fi; }

# the highest version of <pkg> in <range>, worked out from the full version list
expected_in_range() {
  npm view "$1" versions --json | jq -r '.[]' | xargs npx -y semver@7 -r "$2" | tail -n 1
}

echo "Node.js $(node -v), npm $(npm -v)"

echo "== a range picks the highest match, whatever Node.js runs the bot"
# The 2 Nov 2026 bug: on Node 26, npm install homebridge@^1.x.x gave 1.6.1, not 1.11.4.
want=$(expected_in_range homebridge '^1.x.x')
got=$(bash "$RESOLVE" homebridge '"^1.x.x"' 2>/dev/null | cut -f1)
check "homebridge ^1.x.x resolves to $want" "$want" "$got"
check "homebridge ^1.x.x is not 1.6.1" "yes" "$([ "$got" != "1.6.1" ] && echo yes || echo no)"

echo "== a string and a one-item list give the same answer"
a=$(bash "$RESOLVE" homebridge '"^1.x.x"' 2>/dev/null)
b=$(bash "$RESOLVE" homebridge '["^1.x.x"]' 2>/dev/null)
check "string and list agree" "$a" "$b"

echo "== a dist-tag resolves to what npm reports for it"
want=$(npm view homebridge@latest version)
check "homebridge latest" "$want	latest" "$(bash "$RESOLVE" homebridge '"latest"' 2>/dev/null)"

echo "== a list installs the highest of its tags and names the winner"
latest=$(npm view homebridge@latest version)
want="$latest	latest"
check "[^1.x.x, latest] picks latest" "$want" "$(bash "$RESOLVE" homebridge '["^1.x.x", "latest"]' 2>/dev/null)"

echo "== a tag that does not resolve fails the run"
if bash "$RESOLVE" homebridge '"no-such-tag-xyz"' >/dev/null 2>&1; then
  fail "unknown tag exits non-zero"
else
  ok "unknown tag exits non-zero"
fi
if bash "$RESOLVE" homebridge '["latest", "no-such-tag-xyz"]' >/dev/null 2>&1; then
  fail "one bad tag in a list exits non-zero"
else
  ok "one bad tag in a list exits non-zero"
fi
if bash "$RESOLVE" homebridge '[]' >/dev/null 2>&1; then
  fail "empty list exits non-zero"
else
  ok "empty list exits non-zero"
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "All tests passed"
else
  echo "$failed test(s) failed"
  exit 1
fi
