#!/usr/bin/env bash
# Fails when the package graph breaks the app/extension split (PKG-01, PKG-02, PKG-06):
#   SPM:       iOS 15.0 only and swift-tools-version 5.9; exactly two products (NottiSDK, NottiSDKExtension); NottiShared is not a
#              product and depends on nothing; NottiSDKExtension depends only on NottiShared; NottiSDKBootstrap (the ObjC launch hook)
#              depends on nothing, is a dependency of NottiSDK only, and is not reachable from NottiShared or NottiSDKExtension.
#   CocoaPods: allowlist, two root pods and no subspecs (AD-012). NottiSDK.podspec: metadata keys plus exactly the
#              Shared, SDK and bootstrap source globs, the bootstrap header glob and its own resource bundle.
#              NottiSDKExtension.podspec: metadata keys plus exactly the Shared and Extension source globs and its own
#              resource bundle, no dependency (never NottiSDK) and no bootstrap (PKG-07, PODS-04). A subspec, test spec,
#              platform-scoped key or any new key fails on purpose: update this script in the same change.
#
# Needs `swift`, `pod` and `python3` (runs on the macOS CI job).
# Usage: scripts/check-package-graph.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"

# Runs a command and prints its stdout. stderr is kept apart so tool warnings never end
# up in the JSON being parsed; it is shown only when the command fails.
err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT
run() {
  local out
  if ! out="$("$@" 2>"$err_file")"; then
    echo "error: '$*' failed:" >&2
    cat "$err_file" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s' "$out"
}

spm_json="$(run swift package dump-package)"
pod_json="$(run pod ipc spec NottiSDK.podspec)"
ext_json="$(run pod ipc spec NottiSDKExtension.podspec)"

SPM_JSON="$spm_json" POD_JSON="$pod_json" EXT_JSON="$ext_json" python3 - <<'PY'
import json, os, sys

errors = []

spm = json.loads(os.environ["SPM_JSON"])
# PKG-01 and edge case "tools version stays 5.9 so Xcode 15+ can resolve it".
if spm.get("platforms") != [{"platformName": "ios", "version": "15.0", "options": []}]:
    errors.append(f"SPM platforms must be exactly iOS 15.0, got {spm.get('platforms')!r}")
if spm.get("toolsVersion", {}).get("_version") != "5.9.0":
    errors.append(f"SPM swift-tools-version must be 5.9, got {spm.get('toolsVersion')!r}")

products = {p["name"]: p["targets"] for p in spm["products"]}
if products != {"NottiSDK": ["NottiSDK"], "NottiSDKExtension": ["NottiSDKExtension"]}:
    errors.append(f"SPM products must be exactly NottiSDK and NottiSDKExtension, got {products}")

def target_deps(target):
    names = []
    for dep in target.get("dependencies", []):
        # Each dependency is {"byName"|"target"|"product": [name, ...]}.
        kind, value = next(iter(dep.items()))
        names.append(f"{kind}:{value[0]}")
    return sorted(names)

targets = {t["name"]: t for t in spm["targets"] if t["type"] == "regular"}
expected = {
    "NottiShared": [],
    "NottiSDKBootstrap": [],
    "NottiSDKExtension": ["byName:NottiShared"],
    "NottiSDK": ["byName:NottiSDKBootstrap", "byName:NottiShared"],
}
for name, want in expected.items():
    if name not in targets:
        errors.append(f"SPM target {name} is missing")
        continue
    got = target_deps(targets[name])
    if got != want:
        errors.append(f"SPM target {name} must depend on {want or 'nothing'}, got {got}")

# DEL-01, DEL-12: the launch hook is app-only. Nothing reachable from NottiShared or NottiSDKExtension
# (transitively) may be the bootstrap target, and no product other than NottiSDK may contain it.
def reachable(start):
    seen, stack = set(), [start]
    while stack:
        name = stack.pop()
        if name in seen or name not in targets:
            continue
        seen.add(name)
        for dep in target_deps(targets[name]):
            stack.append(dep.split(":", 1)[1])
    return seen

for name in ("NottiShared", "NottiSDKExtension"):
    if name in targets and "NottiSDKBootstrap" in reachable(name):
        errors.append(f"SPM target {name} must never reach NottiSDKBootstrap")
dependents = sorted(n for n, t in targets.items() if "byName:NottiSDKBootstrap" in target_deps(t))
if dependents != ["NottiSDK"]:
    errors.append(f"only NottiSDK may depend on NottiSDKBootstrap (test targets are not checked), got {dependents}")

# Root: metadata and the exact file attributes below. Platform-scoped keys (e.g. "ios"), subspecs, test specs and
# app specs are not allowed because they could pull app code into the extension pod.
meta_allowed = {
    "name", "version", "summary", "description", "homepage", "license", "authors",
    "source", "platforms", "swift_version", "swift_versions", "cocoapods_version",
    "pod_target_xcconfig",
}
swift_flags = {"OTHER_SWIFT_FLAGS": "$(inherited) -package-name NottiSDK"}
expected_pods = {
    "NottiSDK": {
        "source_files": [
            "Sources/NottiShared/**/*.swift",
            "Sources/NottiSDK/**/*.swift",
            "Sources/NottiSDKBootstrap/**/*.{h,m}",
        ],
        "public_header_files": "Sources/NottiSDKBootstrap/include/*.h",
        "resource_bundles": {"NottiSDK_Privacy": ["Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy"]},
    },
    "NottiSDKExtension": {
        "source_files": ["Sources/NottiShared/**/*.swift", "Sources/NottiSDKExtension/**/*.swift"],
        "resource_bundles": {
            "NottiSDKExtension_Privacy": ["Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy"]
        },
    },
}
for env, name in (("POD_JSON", "NottiSDK"), ("EXT_JSON", "NottiSDKExtension")):
    pod = json.loads(os.environ[env])
    want = expected_pods[name]
    if pod.get("name") != name:
        errors.append(f"{name}.podspec must be named {name}, got {pod.get('name')!r}")
    extra = sorted(set(pod) - meta_allowed - set(want))
    if extra:
        errors.append(f"{name}.podspec has keys outside the allowlist: {extra} (subspecs are not allowed, AD-012)")
    if pod.get("platforms") != {"ios": "15.0"}:
        errors.append(f"{name}.podspec platforms must be {{'ios': '15.0'}}, got {pod.get('platforms')!r}")
    if pod.get("pod_target_xcconfig") != swift_flags:
        errors.append(f"{name}.podspec pod_target_xcconfig must be {swift_flags}, got {pod.get('pod_target_xcconfig')!r}")
    for key, value in want.items():
        if pod.get(key) != value:
            errors.append(f"{name}.podspec {key} must be exactly {value}, got {pod.get(key)!r}")

if errors:
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    sys.exit(1)
print("package graph ok")
PY
