#!/usr/bin/env bash
# Fails when the package graph breaks the app/extension split (PKG-01, PKG-02, PKG-06):
#   SPM:       exactly two products (NottiSDK, NottiSDKExtension); NottiShared is not a
#              product and depends on nothing; NottiSDKExtension depends only on NottiShared.
#   CocoaPods: default subspec is Core; Shared depends on nothing; Extension depends only
#              on NottiSDK/Shared; each subspec compiles exactly its own Sources/ folder
#              and ships only its own resources; the root spec adds no files (PKG-07).
#
# Needs `swift`, `pod` and `python3` (runs on the macOS CI job).
# Usage: scripts/check-package-graph.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"

spm_json="$(swift package dump-package)"
pod_json="$(pod ipc spec NottiSDK.podspec)"

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
default = pod.get("default_subspecs")
if default not in ("Core", ["Core"]):
    errors.append(f"podspec default_subspecs must be Core, got {default!r}")

subspecs = {s["name"]: s for s in pod.get("subspecs", [])}
pod_expected = {"Shared": [], "Extension": ["NottiSDK/Shared"]}
for name, want in pod_expected.items():
    if name not in subspecs:
        errors.append(f"podspec subspec {name} is missing")
        continue
    got = sorted(subspecs[name].get("dependencies", {}).keys())
    if got != want:
        errors.append(f"podspec subspec {name} must depend on {want or 'nothing'}, got {got}")

# File patterns: a widened glob (e.g. Shared = 'Sources/**/*.swift') would compile app
# code into the Extension pod without adding any dependency edge.
for key in ("source_files", "resources", "resource_bundles", "vendored_frameworks"):
    if pod.get(key):
        errors.append(f"podspec root must not declare {key}, got {pod[key]!r}")

def as_list(value):
    if value is None:
        return []
    return [value] if isinstance(value, str) else list(value)

pod_files = {
    "Shared": ("Sources/NottiShared/**/*.swift", {}),
    "Core": ("Sources/NottiSDK/**/*.swift",
             {"NottiSDK_Privacy": ["Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy"]}),
    "Extension": ("Sources/NottiSDKExtension/**/*.swift",
                  {"NottiSDKExtension_Privacy": ["Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy"]}),
}
for name, (want_sources, want_bundles) in pod_files.items():
    spec = subspecs.get(name)
    if spec is None:
        continue  # already reported above
    got_sources = as_list(spec.get("source_files"))
    if got_sources != [want_sources]:
        errors.append(f"podspec subspec {name} source_files must be {want_sources!r}, got {got_sources}")
    got_bundles = {k: as_list(v) for k, v in (spec.get("resource_bundles") or {}).items()}
    if got_bundles != want_bundles:
        errors.append(f"podspec subspec {name} resource_bundles must be {want_bundles or 'none'}, got {got_bundles}")
    if as_list(spec.get("resources")):
        errors.append(f"podspec subspec {name} must not declare resources, got {spec.get('resources')!r}")

if errors:
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    sys.exit(1)
print("package graph ok")
PY
