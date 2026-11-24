#!/usr/bin/env bash
# Build the upstream Wikimedia metadata plugin (plugins/examples/wikimedia)
# into <out-dir>/wikimedia.ndp, using the same Go image and module settings as
# the Navidrome build. Plain Go (wasip1), no TinyGo needed.
#   build-wikimedia.sh [out-dir]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mkdir -p "${1:-$root/dist}" && cd "${1:-$root/dist}" && pwd)
go_image=$(sed -nE 's/^FROM .*(golang:[^ ]+-alpine) AS build-alpine$/\1/p' "$root/Dockerfile")
[[ -n $go_image ]] || { echo "build-wikimedia: cannot find Go image in Dockerfile" >&2; exit 2; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
podman run --rm \
  -e GOPROXY=direct -e GOSUMDB=off -e GOTOOLCHAIN=local \
  -e GOOS=wasip1 -e GOARCH=wasm -e CGO_ENABLED=0 \
  -v "$root/plugins:/src/plugins:ro,z" -v "$work:/out:z" \
  -w /src/plugins/examples/wikimedia \
  "$go_image" \
  sh -c 'apk add --no-cache git >/dev/null && go build -buildmode=c-shared -trimpath -o /out/plugin.wasm .'

cp "$root/plugins/examples/wikimedia/manifest.json" "$work/"
rm -f "$out/wikimedia.ndp"
(cd "$work" && python3 -m zipfile -c "$out/wikimedia.ndp" manifest.json plugin.wasm)
echo "build-wikimedia: $out/wikimedia.ndp"
