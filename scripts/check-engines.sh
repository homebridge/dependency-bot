#!/usr/bin/env bash
#
# Warns when a dependency's "engines.node" leaves out the Node.js that the same package.json pins.
# Only for directories that pin "node" as a dependency (as homebridge-apt-pkg's stream files do).
# Warnings only: shipping outside engines can be deliberate.
#
# Usage: check-engines.sh [package.json]
# Prints one line per mismatch, e.g.
#   homebridge 1.11.4 declares Node.js ^18.15.0 || ^20.7.0 || ^22 || ^24; this file pins Node.js 26.13.1
# Always exits 0, unless the file can't be read.

set -euo pipefail

file="${1:-package.json}"

node=$(jq -r '.dependencies.node // empty' "$file")
[ -n "$node" ] || exit 0

while IFS=$'\t' read -r name version; do
  range=$(npm view "$name@$version" engines.node 2>/dev/null || true)
  [ -n "$range" ] || continue

  if ! npx -y semver@7 -r "$range" "$node" >/dev/null 2>&1; then
    echo "$name $version declares Node.js $range; this file pins Node.js $node"
  fi
done < <(jq -r '.dependencies // {} | to_entries[] | select(.key != "node") | [.key, .value] | @tsv' "$file")
