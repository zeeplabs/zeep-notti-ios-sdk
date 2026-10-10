#!/usr/bin/env bash
# Fails when the SDK version drifts between the Swift constant, the podspec
# and (on tag builds) the git tag. PKG-14/15.
#
# Usage: scripts/check-version.sh [repo-root]
# Reads GITHUB_REF (e.g. refs/tags/0.1.0) when set.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
swift_file="$root/Sources/NottiShared/NottiSDKVersion.swift"
podspec="$root/NottiSDK.podspec"

swift_version="$(sed -nE 's/.*static let current = "([^"]+)".*/\1/p' "$swift_file")"
pod_version="$(sed -nE "s/^[[:space:]]*s\.version[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$podspec")"

if [[ -z "$swift_version" || -z "$pod_version" ]]; then
  echo "error: could not read versions (swift='$swift_version', podspec='$pod_version')" >&2
  exit 1
fi

if [[ "$swift_version" != "$pod_version" ]]; then
  echo "error: version drift: NottiSDKVersion.current=$swift_version, NottiSDK.podspec s.version=$pod_version" >&2
  exit 1
fi

ref="${GITHUB_REF:-}"
if [[ "$ref" == refs/tags/* ]]; then
  tag="${ref#refs/tags/}"
  if [[ "$tag" != "$swift_version" ]]; then
    echo "error: version drift: tag=$tag, NottiSDKVersion.current=$swift_version" >&2
    exit 1
  fi
fi

echo "version ok: $swift_version"
