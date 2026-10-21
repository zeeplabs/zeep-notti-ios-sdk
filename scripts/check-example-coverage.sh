#!/usr/bin/env bash
# Fails when a public member of the SDK is not called by the example app (EXR-02, drift guard).
#
# Members come from .specs/codebase/PUBLIC_SURFACE.txt, so a new public member fails this check until the
# example calls it. Scope: `Notti`, `Notti.User`, `Notti.Notifications` (including the delegate forwarding
# methods), `Notti.Options`, the payload fields, `NottiSubscription.remove` and the two
# `NottiNotificationServiceExtension` methods. The Objective-C mirror (Public/ObjC) is out of scope:
# `NottiSDKObjCTests` and `NottiSDKExtensionObjCTests` already compile it.
#
# A name counts only as a qualified SDK call (`Notti.User.setEmail`, `payload.title`, `subscription.remove(`),
# so a model method with the same name does not satisfy it. Comments are stripped first. Textual (grep, sed,
# sort), so it runs on the Linux `checks` job with no Swift toolchain.
#
# Usage: scripts/check-example-coverage.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
surface=".specs/codebase/PUBLIC_SURFACE.txt"
example_dirs=("Example/App" "Example/NotificationService")

# Public names the example cannot call, one per line, with the reason. Empty today: every member in scope
# is callable. Format: `name|reason`.
allowlist=()

cd "$root"

for dir in "${example_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: expected directory not found: $dir" >&2
    exit 1
  fi
done
if [[ ! -f "$surface" ]]; then
  echo "error: surface file not found: $surface" >&2
  exit 1
fi

# Strips `//` and `/* */` comments and the text inside "..." string literals, keeping line breaks, so a
# commented-out call or a call named inside a string does not count. Single-line strings only (no raw or
# multi-line literals in the example).
strip_swift() {
  awk '
    BEGIN { block = 0 }
    {
      out = ""; n = length($0); i = 1; str = 0
      while (i <= n) {
        c = substr($0, i, 1); d = substr($0, i, 2)
        if (block) { if (d == "*/") { block = 0; i += 2 } else i++; continue }
        if (str) {
          if (c == "\\") { i += 2; continue }
          if (c == "\"") { str = 0; out = out "\"" }
          i++; continue
        }
        if (d == "//") break
        if (d == "/*") { block = 1; i += 2; continue }
        if (c == "\"") { str = 1; out = out "\""; i++; continue }
        out = out c; i++
      }
      print out
    }
  ' "$1"
}

example_src="$(find "${example_dirs[@]}" -name '*.swift' -type f | LC_ALL=C sort | while IFS= read -r f; do
  strip_swift "$f"
done)"
if [[ -z "$example_src" ]]; then
  echo "error: no Swift source found under ${example_dirs[*]}" >&2
  exit 1
fi

# Surface line -> "kind name" for the files in scope; kind picks the call shape the example must use.
members="$(awk -F': ' '
  function name_of(line,   m) {
    if (match(line, /(func|var|let)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
      m = substr(line, RSTART, RLENGTH); sub(/^(func|var|let)[[:space:]]+/, "", m); return m
    }
    return ""
  }
  {
    file = $1; line = substr($0, length($1) + 3)
    n = name_of(line)
    if (n == "") next
    if (file ~ /\/Public\/ObjC\//) next
    if (file ~ /Public\/Notti\.swift$/ || file ~ /Public\/NottiNotifications\+Delegate\.swift$/) print "sdk " n
    else if (file ~ /Facade\/NottiNotificationPayload\.swift$/) print "payload " n
    else if (file ~ /Facade\/NottiListenerHub\.swift$/) print "subscription " n
    else if (file ~ /NottiSDKExtension\/NottiNotificationServiceExtension\.swift$/) print "nse " n
  }
' "$surface" | LC_ALL=C sort -u)"

if [[ -z "$members" ]]; then
  echo "error: no public members found in $surface for the example scope" >&2
  exit 1
fi

missing=()
checked=0
while read -r kind name; do
  [[ -z "$name" ]] && continue
  skip=0
  for entry in "${allowlist[@]:-}"; do
    [[ -n "$entry" && "${entry%%|*}" == "$name" ]] && skip=1
  done
  [[ $skip -eq 1 ]] && continue

  case "$kind" in
    sdk)
      # `Notti.Options(baseUrl:` is an initializer argument, not a dotted call.
      if [[ "$name" == "baseUrl" ]]; then pattern='Notti\.Options\(baseUrl:'
      else pattern="Notti(\\.[A-Za-z]+)*\\.${name}([^A-Za-z0-9_]|\$)"; fi ;;
    payload) pattern="payload\\.${name}([^A-Za-z0-9_]|\$)" ;;
    subscription) pattern="subscription\\.${name}\\(" ;;
    nse) pattern="NottiNotificationServiceExtension\\.${name}([^A-Za-z0-9_]|\$)" ;;
    *) echo "error: unknown member kind: $kind" >&2; exit 1 ;;
  esac
  checked=$((checked + 1))
  if ! grep -qE "$pattern" <<<"$example_src"; then
    missing+=("$kind $name")
  fi
done <<<"$members"

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "error: public members not called by the example app (EXR-02):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "Call each one from Example/App or Example/NotificationService, or list it in allowlist with a reason." >&2
  exit 1
fi

# Every instance method of ExampleModel is reachable from a screen: the views call `model.<name>`.
model_file="Example/App/ExampleModel.swift"
views_file="Example/App/ExampleViews.swift"
for f in "$model_file" "$views_file"; do
  if [[ ! -f "$f" ]]; then
    echo "error: expected file not found: $f" >&2
    exit 1
  fi
done
views_src="$(strip_swift "$views_file")"
unwired=()
model_methods="$(strip_swift "$model_file" | sed -nE 's/^[[:space:]]+(@MainActor[[:space:]]+)?func[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/p' | LC_ALL=C sort -u)"
# `static`, `private` and `fileprivate` members are not matched by the pattern above only when they carry the keyword
# before `func`; filter them explicitly from the source lines.
public_methods=""
while read -r name; do
  [[ -z "$name" ]] && continue
  if strip_swift "$model_file" | grep -qE "^[[:space:]]*(private|fileprivate|static)[^{]*func[[:space:]]+${name}\b"; then continue; fi
  public_methods+="$name"$'\n'
done <<<"$model_methods"
while read -r name; do
  [[ -z "$name" ]] && continue
  grep -qE "model\.${name}([^A-Za-z0-9_]|\$)" <<<"$views_src" || unwired+=("$name")
done <<<"$public_methods"
if [[ ${#unwired[@]} -gt 0 ]]; then
  echo "error: ExampleModel methods no screen calls (EXR-02):" >&2
  printf '  %s\n' "${unwired[@]}" >&2
  exit 1
fi

echo "example coverage ok ($checked members)"
