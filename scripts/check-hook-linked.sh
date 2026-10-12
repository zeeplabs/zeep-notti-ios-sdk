#!/usr/bin/env bash
# Proves the Objective-C launch hook (`NottiBootstrap`, DEL-01) is linked and runs, the way an app gets it.
#
#   spm  Builds scripts/hook-consumer (an executable that depends on the package and never names the hook) in
#        Release for an iOS simulator, runs it there and requires `loadCount == 1` and `installCount == 1`:
#        `+load` ran once and found the Swift installer. Fails when the bootstrap target is not linked.
#   pod  Lints NottiSDK.podspec with `pod lib lint --no-clean` and requires `_OBJC_CLASS_$_NottiBootstrap` in
#        the built NottiSDK binary (`nm`). CocoaPods links the pod; this proves the class made it into the product.
#
# The consumer is copied to a temp dir and the package is linked there under its repo name, so the check
# also works in a git worktree or a checkout with a different directory name, and leaves no .build behind.
#
# Needs Xcode (spm: a simulator named $NOTTI_SIM, default "iPhone 17", booted here if needed; pod: `pod`).
# Usage: scripts/check-hook-linked.sh [spm|pod]
set -euo pipefail

mode="${1:-spm}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
booted_by_us=""
udid=""
cleanup() {
  if [[ -n "$booted_by_us" && -n "$udid" ]]; then xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

check_spm() {
  local sim="${NOTTI_SIM:-iPhone 17}"
  udid="$(xcrun simctl list devices available -j | SIM="$sim" python3 -c '
import json, os, sys
want = os.environ["SIM"]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == want and device.get("isAvailable", True):
            print(device["udid"]); sys.exit(0)
sys.exit(1)')" || { echo "error: no available simulator named '$sim' (set NOTTI_SIM)" >&2; exit 1; }
  local booted
  booted="$(xcrun simctl list devices booted)"
  if ! grep -q "$udid" <<<"$booted"; then
    xcrun simctl boot "$udid"
    booted_by_us=1
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null

  # The package under its repo name, next to a copy of the consumer that points at it.
  ln -s "$root" "$tmp/zeep-notti-ios-sdk"
  cp -R "$root/scripts/hook-consumer" "$tmp/hook-consumer"
  rm -rf "$tmp/hook-consumer/.build"
  sed -i.bak 's#path: "../.."#path: "../zeep-notti-ios-sdk"#' "$tmp/hook-consumer/Package.swift"
  rm -f "$tmp/hook-consumer/Package.swift.bak"

  (
    cd "$tmp/hook-consumer"
    xcodebuild build \
      -scheme HookConsumer \
      -destination "platform=iOS Simulator,id=$udid" \
      -configuration Release \
      -derivedDataPath "$tmp/dd" \
      CODE_SIGNING_ALLOWED=NO \
      -quiet
  )

  local binary
  binary="$(find "$tmp/dd/Build/Products/Release-iphonesimulator" -maxdepth 1 -type f -name App -perm -u+x | head -1)"
  if [[ -z "$binary" ]]; then
    echo "error: the consumer binary was not built" >&2
    exit 1
  fi
  local output
  output="$(xcrun simctl spawn "$udid" "$binary" 2>&1)"
  echo "$output"
  if ! grep -qx 'NOTTI_HOOK loadCount=1 installCount=1' <<<"$output"; then
    echo "error: expected 'NOTTI_HOOK loadCount=1 installCount=1' (loadCount=-1 means NottiBootstrap is not linked)" >&2
    exit 1
  fi
  echo "hook linked ok (spm)"
}

check_pod() {
  local log="$tmp/lint.log"
  if ! (cd "$root" && pod lib lint NottiSDK.podspec --platforms=ios --no-clean >"$log" 2>&1); then
    cat "$log" >&2
    echo "error: pod lib lint failed" >&2
    exit 1
  fi
  local workspace lint_dir
  workspace="$(sed -n 's/^Pods workspace available at `\(.*\)` for inspection\.$/\1/p' "$log" | head -1)"
  if [[ -z "$workspace" ]]; then
    echo "error: could not find the kept lint workspace in the pod output" >&2
    exit 1
  fi
  lint_dir="$(dirname "$workspace")"

  # Xcode keys DerivedData by workspace path; find the one for this lint run.
  local derived_root="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}" derived="" candidate
  for candidate in "$derived_root"/App-*; do
    if [[ -f "$candidate/info.plist" && "$(plutil -extract WorkspacePath raw "$candidate/info.plist" 2>/dev/null)" == "$workspace" ]]; then
      derived="$candidate"
      break
    fi
  done
  if [[ -z "$derived" ]]; then
    rm -rf "$lint_dir"
    echo "error: no DerivedData entry for $workspace" >&2
    exit 1
  fi
  local binary="$derived/Build/Products/Release-iphonesimulator/NottiSDK/NottiSDK.framework/NottiSDK"
  local status=0 symbols=""
  # Captured first: `grep -q` closing the pipe early would fail `nm` under pipefail.
  [[ -f "$binary" ]] && symbols="$(nm "$binary" 2>/dev/null || true)"
  if [[ ! -f "$binary" ]]; then
    echo "error: built pod binary not found: $binary" >&2
    status=1
  elif ! grep -q '_OBJC_CLASS_\$_NottiBootstrap' <<<"$symbols"; then
    echo "error: _OBJC_CLASS_\$_NottiBootstrap is missing from the built pod product" >&2
    status=1
  fi
  rm -rf "$lint_dir" "$derived"
  [[ $status -eq 0 ]] || exit 1
  echo "hook linked ok (pod)"
}

case "$mode" in
  spm) check_spm ;;
  pod) check_pod ;;
  *) echo "usage: $0 [spm|pod]" >&2; exit 2 ;;
esac
