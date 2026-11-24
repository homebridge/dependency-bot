#!/usr/bin/env bash
#
# Tests for scripts/check-downgrade.sh and scripts/check-engines.sh.
# The engines tests need network access to the npm registry.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
failed=0

ok() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1${2:+ ($2)}"; failed=$((failed + 1)); }
passes() { if "${@:2}" >/dev/null 2>&1; then ok "$1"; else fail "$1" "exited non-zero"; fi; }
fails() { if "${@:2}" >/dev/null 2>&1; then fail "$1" "exited 0"; else ok "$1"; fi; }

DOWN=scripts/check-downgrade.sh
ENGINES=scripts/check-engines.sh

echo "== check-downgrade: a version must never go down"
fails "the 2 Nov case: homebridge 1.11.4 to 1.6.1 fails" bash "$DOWN" homebridge 1.11.4 1.6.1
passes "1.6.1 to 1.11.4 passes (semver, not text order)" bash "$DOWN" homebridge 1.6.1 1.11.4
passes "the same version passes" bash "$DOWN" homebridge 1.11.4 1.11.4
passes "a prerelease to its release passes" bash "$DOWN" homebridge 2.5.0-beta.3 2.5.0
fails "a release to its own prerelease fails" bash "$DOWN" homebridge 2.5.0 2.5.0-beta.3
fails "beta.11 to beta.7 fails" bash "$DOWN" homebridge 2.5.1-beta.11 2.5.1-beta.7
passes "a new dependency (no current version) passes" bash "$DOWN" homebridge "" 1.0.0
passes "a range in package.json is skipped" bash "$DOWN" homebridge "^1.0.0" 0.9.0
out=$(bash "$DOWN" homebridge 1.11.4 1.6.1 2>&1)
case "$out" in
  *"homebridge would go DOWN from 1.11.4 to 1.6.1"*) ok "the error names the package and both versions" ;;
  *) fail "the error names the package and both versions" "$out" ;;
esac

echo "== check-engines: warn when a dependency leaves out the pinned Node.js"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo '{"dependencies":{"homebridge":"1.11.4","node":"26.13.1"}}' > "$tmp/26.json"
out=$(bash "$ENGINES" "$tmp/26.json")
case "$out" in
  *"homebridge 1.11.4 declares Node.js"*"this file pins Node.js 26.13.1"*) ok "homebridge 1.11.4 on Node 26 warns" ;;
  *) fail "homebridge 1.11.4 on Node 26 warns" "got: '$out'" ;;
esac

echo '{"dependencies":{"homebridge":"1.11.4","node":"24.22.3"}}' > "$tmp/24.json"
out=$(bash "$ENGINES" "$tmp/24.json")
if [ -z "$out" ]; then ok "homebridge 1.11.4 on Node 24 is quiet"; else fail "homebridge 1.11.4 on Node 24 is quiet" "got: '$out'"; fi

echo '{"dependencies":{"homebridge":"1.11.4"}}' > "$tmp/none.json"
out=$(bash "$ENGINES" "$tmp/none.json")
if [ -z "$out" ]; then ok "no node pin, no check"; else fail "no node pin, no check" "got: '$out'"; fi

passes "a warning never fails the run" bash "$ENGINES" "$tmp/26.json"

echo
if [ "$failed" -eq 0 ]; then
  echo "All tests passed"
else
  echo "$failed test(s) failed"
  exit 1
fi
