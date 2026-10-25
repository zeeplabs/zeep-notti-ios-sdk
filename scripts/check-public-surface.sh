#!/usr/bin/env bash
# Fails when the public API surface changes without an update to the committed
# surface file. public-api API-15.
#
# Lists every `public` / `open` declaration line under Sources/NottiSDK and
# Sources/NottiSDKExtension (attributes on the same line are kept, the file path
# is prefixed, the output is sorted) and diffs it with
# .specs/codebase/PUBLIC_SURFACE.txt. Sources/NottiShared must stay `package`:
# any `public` / `open` there fails the check.
#
# Also: every top-level public type in Sources/NottiSDK must carry
# `@available(iOSApplicationExtension, unavailable)` on its declaration line or
# on an attribute line directly above it (API-15 AC 2), unless it is in the
# extension-safe allowlist below. The surface file alone cannot catch a removed
# attribute because it records only the declaration line.
#
# Textual check on purpose: grep/sed/sort/diff only, so it runs on the Linux
# `checks` job with no Swift toolchain. A declaration whose `public` is on a line
# of its own is not caught; the code style keeps modifiers on the declaration line.
#
# Usage:
#   scripts/check-public-surface.sh [repo-root]            check
#   scripts/check-public-surface.sh --update [repo-root]   rewrite the surface file
set -euo pipefail

update=0
if [[ "${1:-}" == "--update" ]]; then
  update=1
  shift
fi
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
surface_file=".specs/codebase/PUBLIC_SURFACE.txt"
api_dirs=("Sources/NottiSDK" "Sources/NottiSDKExtension")
shared_dir="Sources/NottiShared"
ext_attr="@available(iOSApplicationExtension, unavailable)"
# Top-level public types that are extension-safe on purpose, so they carry no
# attribute: NottiSubscription (listener token, no runtime access),
# NottiNotificationPayload, NottiInAppClick and NottiInAppAction (plain value
# types) and NottiLogLevelObjC (plain enum).
# Everything else, including the public `Notti` enum and the ObjC classes, reaches
# `NottiFacade.shared` / `NottiRuntime.shared`, which are unavailable in
# extensions, so it must be marked. A new type needs the attribute or an entry here.
ext_safe_types=" NottiSubscription NottiNotificationPayload NottiLogLevelObjC NottiInAppClick NottiInAppAction "

cd "$root"

# A missing directory must fail the check, not pass it silently (GNU grep exits 2
# on an unreadable path, which would otherwise look like "no match").
for dir in "${api_dirs[@]}" "$shared_dir"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: expected directory not found: $dir" >&2
    exit 1
  fi
done

# A declaration: optional same-line attributes, then public/open and a modifier or
# declaration keyword (so a variable called `open` does not count); or `public`
# after other modifiers such as `private(set)`. A declaration whose parameter list
# continues on the next lines is joined into one entry, so a parameter type change
# is a diff too. Comment lines are skipped. awk is POSIX: present on macOS and on
# the Linux runner.
scan() {
  local files
  files="$(find "$@" -name '*.swift' -type f | LC_ALL=C sort)"
  [[ -z "$files" ]] && return 0
  # shellcheck disable=SC2086
  awk '
    function trim(t) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", t); return t }
    function depth(t,   o, c) { o = gsub(/\(/, "(", t); c = gsub(/\)/, ")", t); return o - c }
    BEGIN {
      kw = "(final|static|class|struct|enum|func|var|let|init|typealias|protocol|extension|subscript|convenience|override|indirect|associatedtype|case|actor|mutating|nonisolated|lazy|weak|unowned|dynamic|required)"
      start = "^[[:space:]]*(@[^[:space:]]+[[:space:]]+)*(public|open)[[:space:]]+" kw
      inner = "[[:space:]](public|open)[[:space:]]+" kw
    }
    FNR == 1 { pending = 0 }
    {
      line = trim($0)
      if (pending) {
        acc = acc " " line; d += depth(line); n++
        if ((d <= 0 && line !~ /,$/) || n >= 12) { print FILENAME ": " acc; pending = 0 }
        next
      }
      if (line ~ /^(\/\/|\*|\/\*)/) next
      if ($0 ~ start || $0 ~ inner) {
        d = depth(line)
        if (d > 0 || line ~ /,$/) { acc = line; n = 0; pending = 1 }
        else print FILENAME ": " line
      }
    }
  ' $files
}

# 1. NottiShared exposes nothing public (AD-006: `package` only).
shared_public="$(scan "$shared_dir")"
if [[ -n "$shared_public" ]]; then
  echo "error: public/open declaration in $shared_dir (use package access):" >&2
  echo "$shared_public" >&2
  exit 1
fi

# 2. App-only public types carry the extension-unavailable attribute (API-15 AC 2).
# Top-level means no indentation. The attribute may share the line or sit on the
# attribute lines directly above (a blank or comment line breaks the chain).
unmarked="$(find "${api_dirs[0]}" -name '*.swift' -type f | LC_ALL=C sort | while IFS= read -r f; do
  awk -v attr="$ext_attr" -v safe="$ext_safe_types" -v file="$f" '
    BEGIN {
      decl = "^(@[^ ]+ +)*(public|open) +(final +)?(class|struct|enum|protocol|actor) +[A-Za-z0-9_]+"
      ok = 0
    }
    {
      if ($0 ~ /^@/ && $0 !~ /(public|open) /) { if (index($0, attr) > 0) ok = 1; next_attr = 1 }
      else next_attr = 0
      if ($0 ~ /^[^ \t\/*]/ && match($0, /(public|open) +(final +)?(class|struct|enum|protocol|actor) +[A-Za-z0-9_]+/)) {
        text = substr($0, RSTART, RLENGTH); n = split(text, w, / +/); name = w[n]
        if (index($0, attr) > 0) ok = 1
        if (!ok && index(safe, " " name " ") == 0) print file ": " name
        ok = 0; next
      }
      if (!next_attr) ok = 0
    }
  ' "$f"
done)"
if [[ -n "$unmarked" ]]; then
  echo "error: public type without $ext_attr (API-15 AC 2):" >&2
  echo "$unmarked" >&2
  echo "Add the attribute, or list the type in ext_safe_types in $0 if it is extension-safe." >&2
  exit 1
fi

# 3. The ObjC launch hook header is the only public ObjC header and declares only
# `NottiBootstrap`. It must be public for the module map (SPM and CocoaPods) but
# it is an implementation detail outside semver (AD-014), so it is not in the
# surface file; this guard keeps anything else from slipping in through it.
bootstrap_include="Sources/NottiSDKBootstrap/include"
if [[ ! -d "$bootstrap_include" ]]; then
  echo "error: expected directory not found: $bootstrap_include" >&2
  exit 1
fi
bootstrap_headers="$(find "$bootstrap_include" -type f | LC_ALL=C sort)"
if [[ "$bootstrap_headers" != "$bootstrap_include/NottiBootstrap.h" ]]; then
  echo "error: $bootstrap_include must contain only NottiBootstrap.h (found:" >&2
  echo "$bootstrap_headers" >&2
  echo "). A new public ObjC header is public API: move it to the surface check first." >&2
  exit 1
fi
bootstrap_decls="$(grep -E '^[[:space:]]*@(interface|protocol)[[:space:]]' "$bootstrap_include/NottiBootstrap.h" \
  | sed -E 's/^[[:space:]]*@(interface|protocol)[[:space:]]+([A-Za-z0-9_]+).*/\1 \2/' || true)"
if [[ "$bootstrap_decls" != "interface NottiBootstrap" ]]; then
  echo "error: NottiBootstrap.h must declare only 'interface NottiBootstrap' (found: ${bootstrap_decls:-nothing})" >&2
  exit 1
fi

# 4. The API surface equals the committed file.
current="$(scan "${api_dirs[@]}" | LC_ALL=C sort)"

if [[ $update -eq 1 ]]; then
  printf '%s\n' "$current" > "$surface_file"
  echo "wrote $surface_file ($(printf '%s\n' "$current" | grep -c . || true) declarations)"
  exit 0
fi

if [[ ! -f "$surface_file" ]]; then
  echo "error: surface file not found: $surface_file (run scripts/check-public-surface.sh --update)" >&2
  exit 1
fi

if ! diff_output="$(diff -u "$surface_file" <(printf '%s\n' "$current"))"; then
  echo "error: public API surface differs from $surface_file ('-' = listed but gone, '+' = new):" >&2
  echo "$diff_output" >&2
  echo "If the change is intended, run scripts/check-public-surface.sh --update and commit the file." >&2
  exit 1
fi

echo "public surface ok ($(printf '%s\n' "$current" | grep -c . || true) declarations)"
