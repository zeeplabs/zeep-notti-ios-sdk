#!/usr/bin/env bash
# Fails when the launch hook does work it must not do before `main` (DEL-14).
#
# `NottiBootstrap +load` and `NottiDelegateInstaller` (the code `+load` runs) must not log through
# Foundation/os, read preferences, touch files or the network, or resolve `NottiRuntime`. The hook only
# looks up a class by name, sends one message and lets the installer swizzle two setters.
#
#   NottiBootstrap.m            NSLog | os_log | NSUserDefaults | NSFileManager | NSURLSession |
#                               dataWithContentsOfFile | NottiRuntime
#   NottiDelegateInstaller.swift  UserDefaults | FileManager | URLSession | NottiRuntime
#
# Comments are stripped first (line numbers are kept), so prose may name these types. String literals
# are not stripped: a banned name inside a string is still reported. Logging through `NottiLogger` is
# allowed here and is bounded by a unit test (nothing above `.debug` on the enabled, valid path).
# Textual (grep and perl only), so it runs on the Linux `checks` job with no Swift toolchain.
#
# Usage: scripts/check-launch-hook-purity.sh [repo-root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
bootstrap="$root/Sources/NottiSDKBootstrap/NottiBootstrap.m"
installer="$root/Sources/NottiSDK/Delegates/NottiDelegateInstaller.swift"
bootstrap_pattern='NSLog|os_log|NSUserDefaults|NSFileManager|NSURLSession|dataWithContentsOfFile|NottiRuntime'
installer_pattern='UserDefaults|FileManager|URLSession|NottiRuntime'

for file in "$bootstrap" "$installer"; do
  if [[ ! -f "$file" ]]; then
    echo "error: expected file not found: $file" >&2
    exit 1
  fi
done

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
check() {
  local file="$1" pattern="$2" matches
  # grep exit codes: 0 = match (violation), 1 = no match, >1 = grep error.
  set +e
  matches="$(strip_comments "$file" | grep -E "$pattern")"
  local code=$?
  set -e
  if [[ $code -eq 0 ]]; then
    echo "error: launch hook must not use $pattern (DEL-14): $file" >&2
    echo "$matches" >&2
    status=1
  elif [[ $code -gt 1 ]]; then
    echo "error: grep failed with status $code" >&2
    exit 1
  fi
}

check "$bootstrap" "$bootstrap_pattern"
check "$installer" "$installer_pattern"

if [[ $status -ne 0 ]]; then
  exit 1
fi
echo "launch hook purity ok"
