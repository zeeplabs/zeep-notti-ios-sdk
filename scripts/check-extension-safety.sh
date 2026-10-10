#!/usr/bin/env bash
# Fails when code shared with, or shipped in, the Notification Service Extension
# uses API that is unavailable in app extensions. PKG-03.
#
# SPM has no APPLICATION_EXTENSION_API_ONLY setting, so this grep is the guard
# for SPM consumers. CocoaPods applies the setting itself for appex targets.
#
# Usage: scripts/check-extension-safety.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
dirs=("$root/Sources/NottiShared" "$root/Sources/NottiSDKExtension")
pattern='UIApplication|import UIKit|beginBackgroundTask|registerForRemoteNotifications|CLLocationManager'

# A missing directory must fail the check, not pass it silently (GNU grep exits 2
# on an unreadable path, which would otherwise look like "no match").
for dir in "${dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: expected directory not found: $dir" >&2
    exit 1
  fi
done

# grep exit codes: 0 = match (unsafe API found), 1 = no match, >1 = grep error.
set +e
matches="$(grep -rnE --include='*.swift' "$pattern" "${dirs[@]}")"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  echo "error: extension-unsafe API in extension-safe targets:" >&2
  echo "$matches" >&2
  exit 1
fi
if [[ $status -gt 1 ]]; then
  echo "error: grep failed with exit code $status" >&2
  exit 1
fi

echo "extension safety ok"
