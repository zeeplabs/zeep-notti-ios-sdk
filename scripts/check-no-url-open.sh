#!/usr/bin/env bash
# Fails when SDK sources call a URL-opening API (DEL-18). The SDK hands a tapped push's `data`, and an In-App
# message's link action, to the host byte for byte and never opens an author link itself: the host decides
# what a link means.
#
# Banned under Sources/NottiSDK and Sources/NottiSDKBootstrap: `UIApplication.shared.open`, `.open(_:options`
# and `openURL`. Textual (grep only), so it runs on the Linux `checks` job with no Swift toolchain.
#
# One exception (AD-019): `allowed_file` below, exactly that path, may contain `UIApplication.shared.open(`.
# It opens only the system notification-settings constant for the In-App `push_permission` button. Its other
# banned tokens still fail, and the same call anywhere else (the file moved or copied included) fails.
# A new entry needs an architecture decision.
#
# Usage: scripts/check-no-url-open.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
dirs=("$root/Sources/NottiSDK" "$root/Sources/NottiSDKBootstrap")
pattern='UIApplication\.shared\.open|\.open\(_:options|openURL'
allowed_file="Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift"

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

if [[ $status -gt 1 ]]; then
  echo "error: grep failed with status $status" >&2
  exit 1
fi

# Drop only the allowlisted file's `UIApplication.shared.open(` lines (grep prints `path:line:text`).
violations=""
if [[ $status -eq 0 ]]; then
  allowed_prefix="$root/$allowed_file:"
  while IFS= read -r match; do
    if [[ "$match" == "$allowed_prefix"* ]]; then
      text="${match#"$allowed_prefix"}"
      text="${text#*:}"
      if [[ "$text" == *"UIApplication.shared.open("* && "$text" != *"openURL"* && "$text" != *".open(_:options"* ]]; then
        continue
      fi
    fi
    violations+="$match"$'\n'
  done <<<"$matches"
fi

if [[ -n "$violations" ]]; then
  echo "error: SDK sources must not open URLs (DEL-18; the one exception is $allowed_file, AD-019):" >&2
  printf '%s' "$violations" >&2
  exit 1
fi
echo "no url open ok"
