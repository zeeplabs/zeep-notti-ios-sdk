#!/usr/bin/env bash
# Fails when SDK sources call a URL-opening API (DEL-18). The SDK hands a tapped push's `data`, and an In-App
# message's link action, to the host byte for byte; outside the two files below it never opens a link.
#
# Banned under Sources/NottiSDK and Sources/NottiSDKBootstrap: `UIApplication.shared.open`, `.open(_:options`
# and `openURL`. Textual (grep only), so it runs on the Linux `checks` job with no Swift toolchain.
#
# Two exceptions, `allowed_files` below, exactly those paths, each allowed only `UIApplication.shared.open(` lines:
# - AD-019: NottiPushPermissionAction.swift opens only the system notification-settings constant for the In-App
#   `push_permission` button.
# - AD-020: NottiInAppURLOpener.swift opens an In-App `url` action in the browser, only an `http`/`https` URL
#   its validator accepted, after the click listeners ran.
# Their other banned tokens still fail, and the same call anywhere else (either file moved or copied included)
# fails. A new entry needs an architecture decision.
#
# Usage: scripts/check-no-url-open.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
dirs=("$root/Sources/NottiSDK" "$root/Sources/NottiSDKBootstrap")
pattern='UIApplication\.shared\.open|\.open\(_:options|openURL'
allowed_files=(
  "Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift"
  "Sources/NottiSDK/InApp/Platform/NottiInAppURLOpener.swift"
)

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

# Drop only the allowlisted files' `UIApplication.shared.open(` lines (grep prints `path:line:text`).
violations=""
if [[ $status -eq 0 ]]; then
  while IFS= read -r match; do
    allowed=0
    for allowed_file in "${allowed_files[@]}"; do
      allowed_prefix="$root/$allowed_file:"
      if [[ "$match" == "$allowed_prefix"* ]]; then
        text="${match#"$allowed_prefix"}"
        text="${text#*:}"
        if [[ "$text" == *"UIApplication.shared.open("* && "$text" != *"openURL"* && "$text" != *".open(_:options"* ]]; then
          allowed=1
        fi
      fi
    done
    [[ $allowed -eq 1 ]] && continue
    violations+="$match"$'\n'
  done <<<"$matches"
fi

if [[ -n "$violations" ]]; then
  echo "error: SDK sources must not open URLs (DEL-18; the exceptions are ${allowed_files[*]}, AD-019 and AD-020):" >&2
  printf '%s' "$violations" >&2
  exit 1
fi
echo "no url open ok"
