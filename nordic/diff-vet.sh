#!/usr/bin/env bash
# nordic diff-vet: review what changed between two refs before shipping.
#   diff-vet.sh <old-ref> <new-ref>
# old-ref is normally the newest vetted/<tag>; new-ref the upstream tag.
# Prints go.mod and ui/package.json changes and newly added Google-owned
# modules (report only). FAILS if runtime code adds an outbound host that is
# not in allowed-hosts.txt.
set -euo pipefail
old=${1:?usage: diff-vet.sh <old-ref> <new-ref>}
new=${2:?usage: diff-vet.sh <old-ref> <new-ref>}
here=$(dirname "$0")
git rev-parse --verify -q "$old^{commit}" >/dev/null || { echo "diff-vet: unknown ref $old" >&2; exit 2; }
git rev-parse --verify -q "$new^{commit}" >/dev/null || { echo "diff-vet: unknown ref $new" >&2; exit 2; }

echo "== diff-vet $old -> $new"
echo
echo "== go.mod changes"
git --no-pager diff --stat=200 "$old" "$new" -- go.mod
git --no-pager diff -U0 "$old" "$new" -- go.mod | grep -E '^[+-][^+-]' || echo "(none)"
echo
echo "== ui/package.json changes"
git --no-pager diff -U0 "$old" "$new" -- ui/package.json | grep -E '^[+-][^+-]' || echo "(none)"
echo
echo "== newly added Google-owned Go modules (review, not a failure)"
google='^(github\.com/google/|github\.com/googleapis/|google\.golang\.org/|cloud\.google\.com/|firebase\.google\.com/)'
mods() { git show "$1:go.mod" | awk '/^require \(/{r=1;next} r&&/^\)/{r=0} r{print $1} /^require [^(]/{print $2}' | sort -u; }
comm -13 <(mods "$old") <(mods "$new") | grep -E "$google" || echo "(none)"
echo

echo "== outbound hosts added in runtime code"
added=$(git --no-pager diff -U0 "$old" "$new" -- . \
  ':(exclude)*_test.go' ':(exclude)**/tests/**' ':(exclude)**/testdata/**' \
  ':(exclude)**/i18n/**' ':(exclude)resources/i18n/**' ':(exclude)docs/**' \
  ':(exclude)*.md' ':(exclude)**/package-lock.json' ':(exclude)go.sum' \
  ':(exclude)plugins/examples/**' ':(exclude).github/**' ':(exclude).forgejo/**' \
  ':(exclude)nordic/**' ':(exclude)*.test.js' ':(exclude)*.test.jsx' \
  ':(exclude)*.svg' ':(exclude)release/**' \
  | grep -E '^\+[^+]' | grep -vE '^\+\s*(//|#|\*|/\*)' \
  | grep -oE 'https?://[A-Za-z0-9.-]+' | sed -E 's#^https?://##' | tr 'A-Z' 'a-z' | sort -u || true)

allowed() {
  local h=$1 e
  while read -r e; do
    [[ -z $e || $e == \#* ]] && continue
    if [[ $e == .* ]]; then
      [[ $h == "${e#.}" || $h == *"$e" ]] && return 0
    else
      [[ $h == "$e" ]] && return 0
    fi
  done < "$here/allowed-hosts.txt"
  return 1
}

bad=0
if [[ -z $added ]]; then echo "(none)"; fi
for h in $added; do
  if allowed "$h"; then echo "  ok      $h"; else echo "  DENIED  $h"; bad=1; fi
done
echo
if [[ $bad -ne 0 ]]; then
  echo "diff-vet: FAIL. Review each DENIED host; if legitimate, add it to nordic/allowed-hosts.txt in its own commit." >&2
  exit 1
fi
echo "diff-vet: pass"
