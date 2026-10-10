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

if matches="$(grep -rnE --include='*.swift' "$pattern" "${dirs[@]}")"; then
  echo "error: extension-unsafe API in extension-safe targets:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "extension safety ok"
