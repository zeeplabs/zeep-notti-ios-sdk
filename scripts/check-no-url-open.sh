#!/usr/bin/env bash
# Fails when SDK sources call a URL-opening API (DEL-18). The SDK hands a tapped push's `data` to the host
# byte for byte and never opens a link itself: the host decides what a link means.
#
# Banned under Sources/NottiSDK and Sources/NottiSDKBootstrap: `UIApplication.shared.open`, `.open(_:options`
# and `openURL`. Textual (grep only), so it runs on the Linux `checks` job with no Swift toolchain.
#
# Usage: scripts/check-no-url-open.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
dirs=("$root/Sources/NottiSDK" "$root/Sources/NottiSDKBootstrap")
pattern='UIApplication\.shared\.open|\.open\(_:options|openURL'

# A missing directory must fail the check, not pass it silently (grep exits 2 on an unreadable path).
for dir in "${dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: expected directory not found: $dir" >&2
    exit 1
  fi
done

# grep exit codes: 0 = match (URL opening found), 1 = no match, >1 = grep error.
set +e
matches="$(grep -rnE --include='*.swift' --include='*.m' --include='*.h' "$pattern" "${dirs[@]}")"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  echo "error: SDK sources must not open URLs (DEL-18):" >&2
  echo "$matches" >&2
  exit 1
elif [[ $status -gt 1 ]]; then
  echo "error: grep failed with status $status" >&2
  exit 1
fi
echo "no url open ok"
