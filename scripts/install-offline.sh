#!/usr/bin/env bash
# Installs the stack from an offline bundle. Needs Docker with Compose, no internet.
#
#   sha256sum -c observability-lab-<commit>.tar.sha256
#   tar -xf observability-lab-<commit>.tar
#   cd observability-lab-<commit>
#   ./install.sh
#
# Steps: verify every file's checksum, load the images, verify each loaded
# image ID against the manifest, then start the stack without pulling anything.
set -euo pipefail
cd "$(dirname "$0")"

echo "== Verifying checksums"
sha256sum -c --quiet SHA256SUMS
echo "   all files match"

echo "== Loading images"
docker load -i images/images.tar.gz

echo "== Verifying image IDs"
while read -r img id; do
  actual="$(docker image inspect --format '{{.Id}}' "$img" 2>/dev/null || true)"
  if [[ "$actual" != "$id" ]]; then
    echo "   MISMATCH: $img"
    echo "     expected $id"
    echo "     got      ${actual:-<missing>}"
    exit 1
  fi
  echo "   ok  $img"
done < <(tr -d '\r' < images/manifest.txt)

cd repo

if [[ ! -f .env ]]; then
  cp .env.example .env
fi
if ! grep -qE '^GRAFANA_ADMIN_PASSWORD=.+' .env; then
  echo
  echo "Set GRAFANA_ADMIN_PASSWORD in $(pwd)/.env, then run ./install.sh again."
  exit 1
fi

if [[ ! -f certs/public/ca.crt ]]; then
  echo "== Creating lab certificates"
  ./scripts/gen-lab-certs.sh
fi

echo "== Validating configuration"
./scripts/check.sh

echo "== Starting stack (no pulls allowed)"
docker compose up -d --pull never
docker compose ps