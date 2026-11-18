#!/bin/bash
#
# Prints the newest version of an npm package that a dist-tag or a version range points at.
#
# Usage: resolve-version.sh <package> <tag or range>
#   resolve-version.sh homebridge latest      -> 2.5.0
#   resolve-version.sh homebridge '^1.x.x'    -> 1.11.4
#
# Why this script exists: the action used to run "npm install <package>@<range>" and let npm pick
# the version. npm skips versions whose "engines" do not allow the Node.js that npm itself runs on.
# When the action's Node.js moved to 26, "homebridge@^1.x.x" became 1.6.1 (the newest 1.x that
# allows any Node.js) and no longer 1.11.4. The package that the bot updates is not run on the
# bot's Node.js, so that rule must not decide the version.
#
# Here "npm view" lists every version the tag or range matches, and the highest one wins.
# A deprecated version is only used when every match is deprecated.
#
# Needs npm, npx and jq. Exit code 1 when nothing matches or npm can not be reached.

set -euo pipefail

PKG="${1:?usage: resolve-version.sh <package> <tag or range>}"
SPEC="${2:?usage: resolve-version.sh <package> <tag or range>}"

if ! json=$(npm view "$PKG@$SPEC" version deprecated --json 2> /dev/null) || [ -z "$json" ]; then
  echo "::error::$PKG@$SPEC did not resolve to a version" >&2
  exit 1
fi

# "npm view" prints one string, a list of strings, or (when a version is deprecated) objects.
mapfile -t versions < <(jq -r '
  def entry:
    if type == "string" then {version: ., deprecated: false}
    elif type == "object" and (.version | type) == "string" then {version: .version, deprecated: ((.deprecated // false) != false)}
    else empty end;
  [(if type == "array" then .[] else . end) | entry] as $all
  | ($all | map(select(.deprecated | not))) as $current
  | (if ($current | length) > 0 then $current else $all end)[].version' <<< "$json" 2> /dev/null)

if [ "${#versions[@]}" -eq 0 ]; then
  echo "::error::$PKG@$SPEC did not resolve to a version" >&2
  exit 1
fi
if [ "${#versions[@]}" -eq 1 ]; then
  echo "${versions[0]}"
  exit 0
fi

# the highest by semver rules (not "sort -V", which ranks 2.5.0-beta.3 above 2.5.0)
highest=$(npx -y semver@7 "${versions[@]}" | tail -n 1)
if [ -z "$highest" ]; then
  echo "::error::Could not pick the highest version of $PKG from [${versions[*]}]" >&2
  exit 1
fi
echo "$highest"
