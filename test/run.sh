#!/usr/bin/env bash
#
# Tests for the dependency bot. No network: "npm" and "npx" are fakes that read saved answers.
#
# - scripts/resolve-version.sh is run directly.
# - The "Process directories and packages" step of action.yml is taken out of the file and run
#   as the script it is, in a throw-away folder.
#
# Needs: bash 4 or newer, jq, python3 with PyYAML (Debian and Ubuntu: apt-get install python3-yaml).
# Usage: test/run.sh

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dependency-bot-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/bin"
ANSWERS="$WORK/answers"
NPM_LOG="$WORK/npm.log"
REAL_PATH="$PATH"
export ANSWERS NPM_LOG REAL_PATH
mkdir -p "$FAKEBIN" "$ANSWERS"
FAILS=0
CHECKS=0

section() { printf '\n== %s\n' "$*"; }
ok() {
  CHECKS=$((CHECKS + 1))
  printf '  ok    %s\n' "$1"
}
fail() {
  CHECKS=$((CHECKS + 1))
  FAILS=$((FAILS + 1))
  printf '  FAIL  %s\n' "$1"
  shift
  [ "$#" -gt 0 ] && printf '        %s\n' "$@"
  return 0
}
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3" "expected: $1" "actual:   $2"; fi; }
assert_contains() {
  case "$1" in
    *"$2"*) ok "$3" ;;
    *) fail "$3" "did not find: $2" "in: $1" ;;
  esac
}
assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3" "found: $2" "in: $1" ;;
    *) ok "$3" ;;
  esac
}

# ---- fake npm and npx ------------------------------------------------------------------------

# answer <package@spec> <what "npm view ... --json" prints for it>
answer() { printf '%s\n' "$2" > "$ANSWERS/$(printf '%s' "$1" | tr '/@^~*<>= ' '_________')"; }

cat > "$FAKEBIN/npm" << 'EOF'
#!/bin/bash
# fake npm: "view" prints a saved answer (or fails), "install" logs and writes package.json
case "$1" in
  view)
    file="$ANSWERS/$(printf '%s' "$2" | tr '/@^~*<>= ' '_________')"
    [ -f "$file" ] || exit 1
    cat "$file"
    ;;
  install)
    echo "install $2" >> "$NPM_LOG"
    name="${2%@*}"
    version="${2##*@}"
    jq --arg n "$name" --arg v "$version" '.dependencies[$n] = $v' package.json > package.json.new && mv package.json.new package.json
    ;;
esac
EOF
cat > "$FAKEBIN/npx" << 'EOF'
#!/bin/bash
# fake "npx -y semver@7 <versions...>": prints the valid versions, lowest first.
# ("~" sorts before everything in "sort -V", which gives semver's order for pre-releases.)
shift 2
for v in "$@"; do
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] && echo "${v/-/\~}"
done | sort -V | sed 's/~/-/'
EOF
chmod +x "$FAKEBIN/npm" "$FAKEBIN/npx"

answer 'homebridge@latest' '"2.5.0"'
answer 'homebridge@beta' '"2.5.1-beta.5"'
answer 'homebridge@^1.x.x' '["1.5.0","1.6.0","1.6.1","1.7.0","1.11.3","1.11.4","1.8.5"]'
answer 'node@^24.x.x' '["24.22.2","24.22.3"]'
answer 'old-thing@^2.x.x' '[{"version":"2.0.0"},{"version":"2.1.0"},{"version":"2.2.0","deprecated":"broken release"}]'
answer 'gone-thing@^1.x.x' '[{"version":"1.0.0","deprecated":"no longer supported"},{"version":"1.1.0","deprecated":"no longer supported"}]'

resolve() {
  OUT=$(PATH="$FAKEBIN:$REAL_PATH" "$BASH" "$REPO/scripts/resolve-version.sh" "$@" 2>&1)
  STATUS=$?
}

section "resolve-version.sh: the newest version a tag or range points at"
resolve homebridge latest
assert_eq "2.5.0" "$OUT" "a tag gives its version"
resolve homebridge '^1.x.x'
assert_eq "1.11.4" "$OUT" "a range gives its highest version, also when npm lists a lower one last"
resolve node '^24.x.x'
assert_eq "24.22.3" "$OUT" "the node package: the highest 24.x"
resolve old-thing '^2.x.x'
assert_eq "2.1.0" "$OUT" "a deprecated version is skipped when another one matches"
resolve gone-thing '^1.x.x'
assert_eq "1.1.0" "$OUT" "when every match is deprecated, the highest is still used"
resolve homebridge '^99.x.x'
assert_eq 1 "$STATUS" "nothing matches: exit code 1"
resolve homebridge nosuchtag
assert_eq 1 "$STATUS" "an unknown tag: exit code 1"

# ---- the step of action.yml ------------------------------------------------------------------

# The "run" text of the step, with the two values GitHub fills in replaced by shell variables.
STEP="$WORK/process-dirs.sh"
if ! python3 - "$REPO/action.yml" > "$STEP" << 'EOF'; then
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
run = next(s["run"] for s in steps if s.get("id") == "process-dirs")
run = run.replace("${{ steps.load-config.outputs.config_abs }}", "$TEST_CONFIG")
run = run.replace("${{ steps.load-config.outputs.dirs_length }}", "$TEST_DIRS_LENGTH")
assert "${{" not in run, "a value from GitHub is not replaced in the test"
print(run)
EOF
  fail "the step can be read from action.yml" "python3 with PyYAML is needed (apt-get install python3-yaml)"
fi

# run_step <config json> <current package.json>: run the step in a fresh project folder
run_step() {
  PROJECT="$WORK/project-$RANDOM"
  mkdir -p "$PROJECT/legacy/64bit" "$PROJECT/tmp"
  printf '%s\n' "$1" > "$PROJECT/config.json"
  printf '%s\n' "$2" > "$PROJECT/legacy/64bit/package.json"
  : > "$NPM_LOG"
  OUT=$(cd "$PROJECT" && PATH="$FAKEBIN:$REAL_PATH" ACTION_PATH="$REPO" RUNNER_TEMP="$PROJECT/tmp" \
    TEST_CONFIG="$PROJECT/config.json" TEST_DIRS_LENGTH=1 "$BASH" -e -o pipefail "$STEP" 2>&1)
  STATUS=$?
}
config() { printf '{"directories":[{"directory":"legacy/64bit","packages":[%s]}]}' "$1"; }

section "the action: a version range ('^1.x.x') installs the highest version of the range"
run_step "$(config '{"name":"homebridge","tag":"^1.x.x"}')" '{"dependencies":{"homebridge":"1.11.3"}}'
assert_eq 0 "$STATUS" "the step works"
assert_eq "install homebridge@1.11.4" "$(cat "$NPM_LOG")" "npm installs exactly 1.11.4 (it is never given the range to choose from)"
assert_eq "1.11.4" "$(jq -r .dependencies.homebridge "$PROJECT/legacy/64bit/package.json")" "package.json pins 1.11.4"

section "the action: a list of tags installs the highest of them"
run_step "$(config '{"name":"homebridge","tag":["beta","latest"]}')" '{"dependencies":{"homebridge":"2.5.0"}}'
assert_eq "install homebridge@2.5.1-beta.5" "$(cat "$NPM_LOG")" "the beta is newer than latest, so the beta is installed"

section "the action: nothing in action.yml lets npm choose from a range"
# shellcheck disable=SC2016 # the texts below are lines of action.yml, not variables to expand here
installs=$(grep -n 'npm install "\$pkg@' "$REPO/action.yml" | grep -v 'npm install "\$pkg@\$version"')
assert_eq "" "$installs" "every 'npm install' of a package uses the exact version that was worked out"
# shellcheck disable=SC2016
assert_not_contains "$(cat "$REPO/action.yml")" 'npm install "$pkg@$tag"' "the old line (npm install pkg@tag) is gone"

printf '\n%d checks, %d failed\n' "$CHECKS" "$FAILS"
[ "$FAILS" -eq 0 ]
