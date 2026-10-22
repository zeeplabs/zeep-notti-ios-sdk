#!/usr/bin/env bash
# Fails when a README code snippet drifts from the example source it is cut from (EXR-13).
#
# Each snippet in README.md is a fenced block right after `<!-- snippet:<id> -->`. Its source is the
# region between `// README:begin <id>` and `// README:end <id>` in exactly one file under Example/App or Example/NotificationService (the app and extension target sources).
# The region is compared after removing its common indentation. The sources are compiled into the
# example app, so a snippet that matches its region also compiles.
#
# Fails on: a missing, edited or duplicated region, a snippet with no region, a region the README does not
# use, or a required id that is absent. Textual (awk, diff), so it runs on the Linux `checks` job.
#
# Usage: scripts/check-readme-snippets.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
readme="$root/README.md"
required=(init identity listeners nse manual-forwarding)

for path in "$readme" "$root/Example"; do
  if [[ ! -e "$path" ]]; then
    echo "error: expected path not found: $path" >&2
    exit 1
  fi
done

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$root/Example/App" "$root/Example/NotificationService" -name '*.swift' | sort)

# Lines of a region, indentation removed. Prints nothing when the region is absent.
region() {
  awk -v id="$1" '
    $0 ~ "^[[:space:]]*// README:begin " id "[[:space:]]*$" { on = 1; next }
    $0 ~ "^[[:space:]]*// README:end " id "[[:space:]]*$" { on = 0; next }
    on { lines[++n] = $0 }
    END {
      min = -1
      for (i = 1; i <= n; i++) {
        if (lines[i] ~ /^[[:space:]]*$/) continue
        match(lines[i], /^[ ]*/)
        if (min < 0 || RLENGTH < min) min = RLENGTH
      }
      if (min < 0) min = 0
      for (i = 1; i <= n; i++) print substr(lines[i], min + 1)
    }
  ' "$2"
}

count_regions() {
  local total=0 hits file
  for file in "${sources[@]}"; do
    hits="$(grep -cE "^[[:space:]]*// README:begin $1[[:space:]]*$" "$file" || true)"
    total=$((total + hits))
  done
  echo "$total"
}

# The fenced block under `<!-- snippet:<id> -->`, without the fence lines.
snippet() {
  awk -v id="$1" '
    $0 == "<!-- snippet:" id " -->" { want = 1; next }
    want && /^```/ { if (on) exit; on = 1; next }
    want && on { print }
  ' "$readme"
}

fail=0

# A region inside a dead conditional block would match the README without being compiled.
dead="$(grep -nE '^[[:space:]]*#if[[:space:]]+(false|0)([[:space:]]|$)' "${sources[@]}" || true)"
if [[ -n "$dead" ]]; then
  echo "error: snippet sources must not use '#if false' or '#if 0':" >&2
  echo "$dead" >&2
  fail=1
fi

# A marker that does not match the strict form is ignored by the id scan, so reject it, and reject a repeated id
# (only the first block would be compared).
loose="$(grep -nE '<!--[[:space:]]*snippet' "$readme" | grep -vE '^[0-9]+:<!-- snippet:[a-z0-9-]+ -->$' || true)"
if [[ -n "$loose" ]]; then
  echo "error: README.md has a snippet marker that is not '<!-- snippet:<id> -->' (lowercase, digits, hyphen):" >&2
  echo "$loose" >&2
  fail=1
fi
dups="$(grep -oE '^<!-- snippet:[a-z0-9-]+ -->$' "$readme" | sort | uniq -d || true)"
if [[ -n "$dups" ]]; then
  echo "error: README.md repeats a snippet id:" >&2
  echo "$dups" >&2
  fail=1
fi

readme_ids="$(grep -oE '^<!-- snippet:[a-z0-9-]+ -->$' "$readme" | sed -E 's/^<!-- snippet:(.*) -->$/\1/' | sort)"
region_ids="$(grep -rhoE '// README:begin [a-z0-9-]+' "$root/Example/App" "$root/Example/NotificationService" --include='*.swift' | sed -E 's|// README:begin ||' | sort)"

for id in "${required[@]}"; do
  if ! grep -qx "$id" <<<"$readme_ids"; then
    echo "error: README.md has no snippet '$id'" >&2
    fail=1
  fi
done

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if ! grep -qx "$id" <<<"$region_ids"; then
    echo "error: README snippet '$id' has no README:begin region under Example/" >&2
    fail=1
  fi
done <<<"$readme_ids"

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if ! grep -qx "$id" <<<"$readme_ids"; then
    echo "error: region '$id' under Example/ is not used by the README" >&2
    fail=1
  fi
done <<<"$region_ids"

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  regions="$(count_regions "$id")"
  if [[ "$regions" -ne 1 ]]; then
    echo "error: region '$id' appears $regions times under Example/ (expected 1)" >&2
    fail=1
    continue
  fi
  source_file=""
  for file in "${sources[@]}"; do
    if grep -qE "^[[:space:]]*// README:begin $id[[:space:]]*$" "$file"; then source_file="$file"; fi
  done
  expected="$(region "$id" "$source_file")"
  actual="$(snippet "$id")"
  if [[ -z "$expected" ]]; then
    echo "error: region '$id' in ${source_file#"$root"/} is empty or never closed" >&2
    fail=1
  elif [[ "$expected" != "$actual" ]]; then
    echo "error: README snippet '$id' differs from ${source_file#"$root"/}:" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    fail=1
  fi
done <<<"$readme_ids"

[[ $fail -eq 0 ]] || exit 1
echo "readme snippets ok"
