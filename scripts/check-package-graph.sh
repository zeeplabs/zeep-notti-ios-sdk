#!/usr/bin/env bash
# Fails when the package graph breaks the app/extension split (PKG-01, PKG-02, PKG-06):
#   SPM:       exactly two products (NottiSDK, NottiSDKExtension); NottiShared is not a
#              product and depends on nothing; NottiSDKExtension depends only on NottiShared.
#   CocoaPods: allowlist. The root spec may only carry metadata keys (no files, no
#              platform-scoped attributes); the subspecs are exactly Shared, Core and
#              Extension, each equal to its expected shape (own Sources/ folder, own
#              resources, Extension -> NottiSDK/Shared only), with nothing nested (PKG-07).
#              Any new key fails on purpose: update this script in the same change.
#
# Needs `swift`, `pod` and `python3` (runs on the macOS CI job).
# Usage: scripts/check-package-graph.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"

run() {
  local out
  if ! out="$("$@" 2>&1)"; then
    echo "error: '$*' failed:" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s' "$out"
}

spm_json="$(run swift package dump-package)"
pod_json="$(run pod ipc spec NottiSDK.podspec)"

SPM_JSON="$spm_json" POD_JSON="$pod_json" python3 - <<'PY'
import json, os, sys

errors = []

spm = json.loads(os.environ["SPM_JSON"])
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
    "NottiSDKExtension": ["byName:NottiShared"],
}
for name, want in expected.items():
    if name not in targets:
        errors.append(f"SPM target {name} is missing")
        continue
    got = target_deps(targets[name])
    if got != want:
        errors.append(f"SPM target {name} must depend on {want or 'nothing'}, got {got}")

pod = json.loads(os.environ["POD_JSON"])

# Root: metadata only. Platform-scoped keys (e.g. "ios"), files and test/app specs are
# not allowed because they could pull app code into the Extension subspec.
root_allowed = {
    "name", "version", "summary", "description", "homepage", "license", "authors",
    "source", "platforms", "swift_version", "swift_versions", "cocoapods_version",
    "pod_target_xcconfig", "default_subspecs", "subspecs",
}
extra_root = sorted(set(pod) - root_allowed)
if extra_root:
    errors.append(f"podspec root has keys outside the allowlist: {extra_root}")
if pod.get("platforms") != {"ios": "15.0"}:
    errors.append(f"podspec platforms must be {{'ios': '15.0'}}, got {pod.get('platforms')!r}")
if pod.get("default_subspecs") not in ("Core", ["Core"]):
    errors.append(f"podspec default_subspecs must be Core, got {pod.get('default_subspecs')!r}")

# Subspecs: exact shapes. Equality also rejects platform-scoped keys, nested subspecs,
# extra dependencies, widened globs and borrowed resources.
expected_subspecs = [
    {"name": "Shared", "source_files": "Sources/NottiShared/**/*.swift"},
    {
        "name": "Core",
        "dependencies": {"NottiSDK/Shared": []},
        "source_files": "Sources/NottiSDK/**/*.swift",
        "resource_bundles": {"NottiSDK_Privacy": ["Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy"]},
    },
    {
        "name": "Extension",
        "dependencies": {"NottiSDK/Shared": []},
        "source_files": "Sources/NottiSDKExtension/**/*.swift",
        "resource_bundles": {
            "NottiSDKExtension_Privacy": ["Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy"]
        },
    },
]
got_subspecs = pod.get("subspecs", [])
got_names = [sub.get("name") for sub in got_subspecs]
want_names = [sub["name"] for sub in expected_subspecs]
if got_names != want_names:
    errors.append(f"podspec subspecs must be exactly {want_names}, got {got_names}")
for want in expected_subspecs:
    got = next((sub for sub in got_subspecs if sub.get("name") == want["name"]), None)
    if got is not None and got != want:
        errors.append(f"podspec subspec {want['name']} must be exactly {want}, got {got}")

if errors:
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    sys.exit(1)
print("package graph ok")
PY
