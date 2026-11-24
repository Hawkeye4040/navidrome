#!/usr/bin/env bash
# nordic deny-list guard. Fail-closed: any hit, or any scan error, exits non-zero.
#   deny-list.sh source [repo-dir]      scan runtime source
#   deny-list.sh image <image-ref>      podman save the image and scan its bytes
set -euo pipefail

SOURCE_PATTERNS='google-analytics\.com|googletagmanager\.com|googleapis\.com|gstatic\.com|doubleclick\.net|youtube\.com|insights\.navidrome\.org|from ['"'"'"]react-ga|require\(['"'"'"]react-ga|"react-ga"'
# The image carries ffmpeg/mpv too, so only hunt for the two things we removed.
IMAGE_PATTERNS='google-analytics\.com|googletagmanager\.com|insights\.navidrome\.org'

EXCEPTIONS="$(dirname "$0")/deny-list.exceptions"

# Drop hits matching an exact (path, literal) pair from deny-list.exceptions.
# A hit line is only excused if the literal is the sole denied match on it.
filter_exceptions() {
  local dir=$1 line path rel ex_path ex_lit _ excused rest why
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    path=${line%%:*}; rel=${path#"$dir"/}; rel=${rel#./}
    excused=0
    while IFS='|' read -r ex_path ex_lit _; do
      [[ -z $ex_path || $ex_path == \#* ]] && continue
      if [[ $rel == "$ex_path" && $line == *"$ex_lit"* ]]; then
        rest=${line//"$ex_lit"/}
        grep -qE "$SOURCE_PATTERNS" <<<"$rest" || { excused=1; why=$ex_lit; }
      fi
    done < "$EXCEPTIONS"
    [[ $excused -eq 1 ]] && echo "deny-list: excused $rel ($why)" >&2 || echo "$line"
  done
}

scan_source() {
  local dir=${1:-.} out rc
  set +e
  out=$(grep -rInE "$SOURCE_PATTERNS" "$dir" \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=i18n \
    --exclude-dir=tests --exclude-dir=testdata --exclude-dir=docs \
    --exclude-dir=examples --exclude-dir=nordic --exclude-dir=.github \
    --exclude-dir=.forgejo --exclude-dir=build \
    --exclude='*_test.go' --exclude='*.test.js' --exclude='*.test.jsx' \
    --exclude='*.md' --exclude='package-lock.json' --exclude='go.sum' \
    | grep -vE '^[^:]+:[0-9]+:\s*(//|\*|/\*)')
  rc=$?
  set -e
  # grep exit 1 = no match (good). Anything >1 is a scan error.
  if [[ $rc -gt 1 ]]; then echo "deny-list: source scan error" >&2; exit 2; fi
  out=$(filter_exceptions "$dir" <<<"$out")
  if [[ -n $out ]]; then
    echo "deny-list: FAIL, denied references in runtime source:" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "deny-list: source clean"
}

scan_image() {
  local ref=${1:?image ref required} tmp rc
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  podman save --format docker-archive -o "$tmp/image.tar" "$ref"
  [[ -s $tmp/image.tar ]] || { echo "deny-list: empty image archive" >&2; exit 2; }
  set +e
  grep -aoE "$IMAGE_PATTERNS" "$tmp/image.tar" | sort | uniq -c
  rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -eq 0 ]]; then echo "deny-list: FAIL, denied hosts inside image $ref" >&2; exit 1; fi
  if [[ $rc -gt 1 ]]; then echo "deny-list: image scan error" >&2; exit 2; fi
  echo "deny-list: image $ref clean"
}

case ${1:-} in
  source) scan_source "${2:-.}" ;;
  image)  scan_image "${2:-}" ;;
  *) echo "usage: $0 source [dir] | image <ref>" >&2; exit 2 ;;
esac
