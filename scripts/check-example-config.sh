#!/usr/bin/env bash
# Guards the example's configuration (EXR-04, EXR-06).
#
# 1. The two Info.plists differ only by the `NottiDisableSwizzling` Boolean `true` (EXR-04): `Info.plist` has no
#    such key, `Info-Manual.plist` has exactly that key with `<true/>`.
# 2. The committed sample holds `fixture` for the app id and the client key (EXR-05, EXR-06).
# 3. No tracked file under Example/, README.md or docs/ holds a client or REST key (`ck_`/`rk_` + 64 hex) or a
#    UUID assigned to NOTTI_APP_ID (EXR-06).
#
# Textual (grep, sed, diff), so it runs on the Linux `checks` job. After a build, assert the built plist type
# (a build-setting substitution would turn the Boolean into a string and the SDK would warn):
#   scripts/check-example-config.sh --built <path to the built Info.plist> manual|default
#
# Usage: scripts/check-example-config.sh [repo-root]
set -euo pipefail

if [[ "${1:-}" == "--built" ]]; then
  plist="${2:?usage: --built <Info.plist> manual|default}"
  mode="${3:?usage: --built <Info.plist> manual|default}"
  if [[ ! -f "$plist" ]]; then
    echo "error: built Info.plist not found: $plist" >&2
    exit 1
  fi
  if ! command -v plutil >/dev/null 2>&1; then
    echo "error: plutil not found (run --built on macOS)" >&2
    exit 1
  fi
  if [[ "$mode" == "manual" ]]; then
    type="$(plutil -type NottiDisableSwizzling "$plist" 2>/dev/null || true)"
    if [[ "$type" != "bool" ]]; then
      echo "error: NottiDisableSwizzling in the built Debug-Manual plist must be a bool (got: ${type:-missing})" >&2
      exit 1
    fi
    value="$(plutil -extract NottiDisableSwizzling raw "$plist")"
    if [[ "$value" != "true" ]]; then
      echo "error: NottiDisableSwizzling in the built Debug-Manual plist must be true (got: $value)" >&2
      exit 1
    fi
  else
    if plutil -type NottiDisableSwizzling "$plist" >/dev/null 2>&1; then
      echo "error: the default build must not carry NottiDisableSwizzling" >&2
      exit 1
    fi
  fi
  echo "built plist ok ($mode)"
  exit 0
fi

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
default_plist="Example/App/Info.plist"
manual_plist="Example/App/Info-Manual.plist"
sample="Example/Config/Example.xcconfig.sample"

cd "$root"
for f in "$default_plist" "$manual_plist" "$sample"; do
  if [[ ! -f "$f" ]]; then
    echo "error: expected file not found: $f" >&2
    exit 1
  fi
done

# 1. Plists. Drop the key line and the value line after it from the manual plist, then it must equal the default.
if grep -q 'NottiDisableSwizzling' "$default_plist"; then
  echo "error: $default_plist must not carry NottiDisableSwizzling" >&2
  exit 1
fi
if [[ "$(grep -c '<key>NottiDisableSwizzling</key>' "$manual_plist")" -ne 1 ]]; then
  echo "error: $manual_plist must carry NottiDisableSwizzling exactly once" >&2
  exit 1
fi
if ! grep -A1 '<key>NottiDisableSwizzling</key>' "$manual_plist" | tail -n 1 | grep -qE '^[[:space:]]*<true/>[[:space:]]*$'; then
  echo "error: NottiDisableSwizzling in $manual_plist must be a Boolean <true/>" >&2
  exit 1
fi
stripped="$(awk '/<key>NottiDisableSwizzling<\/key>/ { skip = 2 } skip > 0 { skip--; next } { print }' "$manual_plist")"
if ! diff_output="$(diff -u "$default_plist" <(printf '%s\n' "$stripped"))"; then
  echo "error: $default_plist and $manual_plist differ by more than NottiDisableSwizzling:" >&2
  echo "$diff_output" >&2
  exit 1
fi

# 2. Sample values.
for key in NOTTI_APP_ID NOTTI_CLIENT_KEY; do
  value="$(grep -E "^${key}[[:space:]]*=" "$sample" | head -n 1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//')"
  if [[ "$value" != "fixture" ]]; then
    echo "error: $sample must set $key = fixture (got: ${value:-missing})" >&2
    exit 1
  fi
done

# 3. No real config in tracked files. git ls-files skips the git-ignored local xcconfig.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files="$(git ls-files Example README.md docs 2>/dev/null || true)"
else
  files="$(find Example README.md docs -type f 2>/dev/null | grep -v 'Example.local.xcconfig' || true)"
fi
key_pattern='(^|[^[:alnum:]_])(ck|rk)_[0-9a-fA-F]{64}([^[:alnum:]_]|$)'
uuid_pattern='NOTTI_APP_ID[[:space:]]*=[[:space:]]*[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
leaks=""
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  hit="$(grep -nEH "$key_pattern|$uuid_pattern" "$f" || true)"
  # Never echo the matched value: print the location only.
  [[ -n "$hit" ]] && leaks+="$(printf '%s\n' "$hit" | cut -d: -f1,2)"$'\n'
done <<<"$files"
if [[ -n "$leaks" ]]; then
  echo "error: a client/REST key or a real app id is committed (EXR-06), at:" >&2
  printf '%s' "$leaks" >&2
  exit 1
fi

echo "example config ok"
