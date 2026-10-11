#!/usr/bin/env bash
# Fails when the Notification Service Extension code can leak through a log (NSE-13, NSE-14).
#
# Under Sources/NottiSDKExtension every .swift file must log only through `NottiLogger`, and never print
# `localizedDescription` (URLSession errors carry the media URL, which can hold ids or tokens). Banned:
#
#   NSLog | print( | debugPrint | dump( | os_log | localizedDescription
#
# Comments are stripped first (line numbers are kept), so prose may name these. String literals are not
# stripped: a banned name inside a string is still reported. `print(`, `dump(` and `debugPrint` match only
# as a whole word, so `blueprint(` or `isDumping` do not trip them.
# Textual (grep and perl only), so it runs on the Linux `checks` job with no Swift toolchain.
#
# Usage: scripts/check-nse-logging.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
dir="$root/Sources/NottiSDKExtension"
pattern='(^|[^A-Za-z0-9_])(NSLog|print[[:space:]]*\(|debugPrint|dump[[:space:]]*\(|os_log|localizedDescription)'

if [[ ! -d "$dir" ]]; then
  echo "error: expected directory not found: $dir" >&2
  exit 1
fi

# Prints "line:code" for each line with comments blanked, keeping line numbers.
strip_comments() {
  perl -ne '
    our $in;
    my $out = "";
    my $rest = $_;
    while (length $rest) {
      if ($in) {
        if ($rest =~ s{^.*?\*/}{}s) { $in = 0 } else { $rest = "" }
      } elsif ($rest =~ s{^(.*?)(/\*|//)}{}s) {
        $out .= $1;
        if ($2 eq "/*") { $in = 1 } else { $rest = "" }
      } else {
        $out .= $rest; $rest = "";
      }
    }
    print "$.:$out\n";
  ' "$1"
}

status=0
count=0
while IFS= read -r file; do
  count=$((count + 1))
  # grep exit codes: 0 = match (violation), 1 = no match, >1 = grep error.
  set +e
  matches="$(strip_comments "$file" | grep -E "$pattern")"
  code=$?
  set -e
  if [[ $code -eq 0 ]]; then
    echo "error: the extension must log only through NottiLogger and never use NSLog, print(, debugPrint, dump(, os_log or localizedDescription (NSE-13): $file" >&2
    echo "$matches" >&2
    status=1
  elif [[ $code -gt 1 ]]; then
    echo "error: grep failed with status $code" >&2
    exit 1
  fi
done < <(find "$dir" -name '*.swift' -type f | sort)

if [[ $count -eq 0 ]]; then
  echo "error: no Swift files under $dir" >&2
  exit 1
fi
if [[ $status -ne 0 ]]; then
  exit 1
fi
echo "extension logging ok ($count files)"
