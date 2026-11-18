#!/bin/bash
#
# Stops the bot from moving a package to a LOWER version than the one that is pinned now.
#
# Usage: check-downgrade.sh <package> <current version> <new version> [allow]
#   allow: "true" turns the stop into a warning (the "allow_downgrade" setting of the package).
#
# Exit code 0: the new version is the same or higher (or the current one is not a plain version).
# Exit code 1: the new version is lower, and that is not allowed.
#
# A version only goes down when something is wrong (a tag was moved back, or a lookup went wrong),
# and the packages this bot updates are shipped to users without a review. So stop and let a
# person decide.

set -euo pipefail

PKG="${1:?usage: check-downgrade.sh <package> <current version> <new version> [allow]}"
CURRENT="${2:-}"
NEW="${3:?usage: check-downgrade.sh <package> <current version> <new version> [allow]}"
ALLOW="${4:-false}"

# nothing pinned yet, or no change: nothing to check
if [ -z "$CURRENT" ] || [ "$CURRENT" = "$NEW" ]; then
  exit 0
fi

# "semver" prints the versions it understands, lowest first. A current value that is not a
# plain version (a range, a URL) is left out, and then there is nothing to compare.
mapfile -t sorted < <(npx -y semver@7 "$CURRENT" "$NEW" 2> /dev/null || true)
if [ "${#sorted[@]}" -ne 2 ]; then
  exit 0
fi

if [ "${sorted[1]}" = "$CURRENT" ]; then
  if [ "$ALLOW" = "true" ]; then
    echo "::warning::$PKG goes DOWN from $CURRENT to $NEW (allowed by allow_downgrade)"
    exit 0
  fi
  echo "::error::$PKG would go DOWN from $CURRENT to $NEW. Stopped. If this is wanted, set \"allow_downgrade\": true for this package in the config file, and remove it again afterwards."
  exit 1
fi
