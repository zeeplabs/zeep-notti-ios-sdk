#!/usr/bin/env bash
# Fails when the SDK version drifts between the Swift constant, the two podspecs
# (NottiSDK and NottiSDKExtension), the top released CHANGELOG section and (on tag builds) the git tag.
# PKG-14/15, PODS-05, EXR-21.
#
# The top released section is the first `## [x.y.z] - <date>` heading; `## [Unreleased]` is skipped. Its date is
# `YYYY-MM-DD`, or `TBD` until release day; a tag build requires a real date.
#
# Usage: scripts/check-version.sh [repo-root]
# Reads GITHUB_REF (e.g. refs/tags/0.1.0) when set.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
swift_file="$root/Sources/NottiShared/NottiSDKVersion.swift"
podspec="$root/NottiSDK.podspec"
ext_podspec="$root/NottiSDKExtension.podspec"

swift_version="$(sed -nE 's/.*static let current = "([^"]+)".*/\1/p' "$swift_file")"
pod_version_of() {
  sed -nE "s/^[[:space:]]*s\.version[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$1"
}
pod_version="$(pod_version_of "$podspec")"
ext_version="$(pod_version_of "$ext_podspec")"

if [[ -z "$swift_version" || -z "$pod_version" || -z "$ext_version" ]]; then
  echo "error: could not read versions (swift='$swift_version', NottiSDK.podspec='$pod_version', NottiSDKExtension.podspec='$ext_version')" >&2
  exit 1
fi

if [[ "$swift_version" != "$pod_version" ]]; then
  echo "error: version drift: NottiSDKVersion.current=$swift_version, NottiSDK.podspec s.version=$pod_version" >&2
  exit 1
fi

if [[ "$swift_version" != "$ext_version" ]]; then
  echo "error: version drift: NottiSDKVersion.current=$swift_version, NottiSDKExtension.podspec s.version=$ext_version" >&2
  exit 1
fi

changelog="$root/CHANGELOG.md"
if [[ ! -f "$changelog" ]]; then
  echo "error: CHANGELOG.md not found" >&2
  exit 1
fi
top_heading="$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+[^]]*\]' "$changelog" || true)"
if [[ -z "$top_heading" ]]; then
  echo "error: CHANGELOG.md has no released section (expected '## [x.y.z] - YYYY-MM-DD')" >&2
  exit 1
fi
changelog_version="$(sed -E 's/^## \[([^]]+)\].*/\1/' <<<"$top_heading")"
changelog_date="$(sed -nE 's/^## \[[^]]+\][[:space:]]+-[[:space:]]+(.*[^[:space:]])[[:space:]]*$/\1/p' <<<"$top_heading")"

if [[ "$swift_version" != "$changelog_version" ]]; then
  echo "error: version drift: NottiSDKVersion.current=$swift_version, top CHANGELOG section=$changelog_version" >&2
  exit 1
fi

if [[ ! "$changelog_date" =~ ^([0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])|TBD)$ ]]; then
  echo "error: top CHANGELOG section '$top_heading' needs a date (YYYY-MM-DD) or TBD" >&2
  exit 1
fi

ref="${GITHUB_REF:-}"
if [[ "$ref" == refs/tags/* ]]; then
  tag="${ref#refs/tags/}"
  if [[ "$tag" != "$swift_version" ]]; then
    echo "error: version drift: tag=$tag, NottiSDKVersion.current=$swift_version" >&2
    exit 1
  fi
  if [[ "$changelog_date" == "TBD" ]]; then
    echo "error: tag $tag needs a dated CHANGELOG section (found TBD)" >&2
    exit 1
  fi
  if grep -qiE 'release candidate|pre-release' "$root/README.md"; then
    echo "error: tag $tag but README.md still says release candidate or pre-release (flip the banner first)" >&2
    exit 1
  fi
fi

echo "version ok: $swift_version"
