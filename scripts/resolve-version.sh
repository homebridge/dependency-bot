#!/usr/bin/env bash
#
# Resolves a package's "tag" rule to one exact version. Installs nothing.
#
# Usage: resolve-version.sh <package> <tag-json>
#   tag-json: a JSON string ("latest", "beta", "^1.x.x") or a list of them (["beta", "latest"]).
# Prints: <version><TAB><the tag(s) that gave that version>
# Exit 1 when any tag does not resolve, so a typo or npm hiccup never picks an older version.
#
# Why npm view, and never `npm install <range>`: npm install skips versions whose "engines" field
# leaves out the Node.js that runs it. On 2 Nov 2026 setup-node's lts/* moved to Node 26, and
# homebridge@^1.x.x installed 1.6.1 instead of 1.11.4 (1.7 to 1.11 list Node 24 at most).
# npm view ignores engines. Versions are ranked with semver, not sort -V, which puts
# 2.5.0-beta.3 above 2.5.0.

set -euo pipefail

pkg="${1:?usage: resolve-version.sh <package> <tag-json>}"
tags_json="${2:?usage: resolve-version.sh <package> <tag-json>}"

# highest <version>...: the highest version by semver
highest() { npx -y semver@7 "$@" | tail -n 1; }

candidates=()
sources=()

while IFS= read -r t; do
  # A range can match many versions; npm lists them in publish order, not semver order.
  versions=()
  while IFS= read -r v; do
    [ -n "$v" ] && versions+=("$v")
  done < <(npm view "$pkg@$t" version --json 2>/dev/null |
    jq -r 'if type == "array" then .[] elif type == "string" then . else empty end' 2>/dev/null || true)

  if [ ${#versions[@]} -eq 0 ]; then
    echo "::error::$pkg@$t did not resolve to a version" >&2
    exit 1
  fi

  best=$(highest "${versions[@]}")
  candidates+=("$best")
  sources+=("$t=$best")
  echo "$pkg@$t resolves to $best" >&2
done < <(jq -r 'if type == "array" then .[] else . end' <<<"$tags_json")

if [ ${#candidates[@]} -eq 0 ]; then
  echo "::error::The tag list for $pkg is empty" >&2
  exit 1
fi

version=$(highest "${candidates[@]}")

winner=""
for sv in "${sources[@]}"; do
  [ "${sv#*=}" = "$version" ] && winner="${winner:+$winner, }${sv%%=*}"
done

printf '%s\t%s\n' "$version" "$winner"
