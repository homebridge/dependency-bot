#!/usr/bin/env bash
#
# Stops a version from going DOWN. Run before the bot installs a newly resolved version.
#
# Usage: check-downgrade.sh <package> <current> <new>
#   current: the version in package.json now (may be empty, or a range, which are skipped)
# Exit 0 when <new> is the same or higher, or <current> is not an exact version.
# Exit 1 (with an ::error::) when <new> is lower than <current>.
#
# Why: on 2 Nov 2026 a resolution bug moved homebridge-apt-pkg's legacy stream from Homebridge
# 1.11.4 down to 1.6.1, and the bot pushed it with nothing noticing.
# Ranked with semver, so 2.5.0 is above 2.5.0-beta.3.

set -euo pipefail

pkg="${1:?usage: check-downgrade.sh <package> <current> <new>}"
current="${2-}"
new="${3:?usage: check-downgrade.sh <package> <current> <new>}"

# Nothing to compare: a new dependency, or a range / tag / URL rather than an exact version.
[ -n "$current" ] || exit 0
npx -y semver@7 "$current" >/dev/null 2>&1 || exit 0
[ "$current" != "$new" ] || exit 0

lowest=$(npx -y semver@7 "$current" "$new" | head -n 1)

if [ "$lowest" = "$new" ]; then
  echo "::error::$pkg would go DOWN from $current to $new. Set allow_downgrade: true on this package if that is wanted."
  exit 1
fi
