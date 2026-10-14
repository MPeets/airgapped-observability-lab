#!/usr/bin/env bash
# Builds an offline install bundle. Run on a machine WITH internet access.
#
#   ./scripts/bundle.sh
#
# Output: dist/observability-lab-<commit>.tar and a .sha256 file next to it.
# Carry both across the air gap (approved USB, data diode, transfer station).
#
# The bundle contains:
#   repo/       the committed repository (git archive, so no .env, certs or junk)
#   images/     every container image the stack uses + a manifest of image IDs
#   vendor/     anything you put in ./vendor (e.g. the windows_exporter MSI)
#   install.sh  the offline installer
#   SHA256SUMS  checksums of all of the above
#
# Versions come from .env.example (the committed source of truth), not your
# local .env, so the bundle always matches the commit it was built from.
#
# SKIP_PULL=1 uses images already present locally instead of pulling.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" && "${ALLOW_DIRTY:-0}" != 1 ]]; then
  echo "Working tree has uncommitted changes. Commit first, so the bundle"
  echo "matches a commit (or set ALLOW_DIRTY=1 to override)."
  exit 1
fi

COMMIT="$(git rev-parse --short HEAD)"
NAME="observability-lab-$COMMIT"
STAGE="dist/$NAME"
rm -rf "$STAGE" "dist/$NAME.tar" "dist/$NAME.tar.sha256"
mkdir -p "$STAGE/repo" "$STAGE/images"

echo "== Exporting repository at $COMMIT"
git archive --format=tar HEAD | tar -x -C "$STAGE/repo"
cp scripts/install-offline.sh "$STAGE/install.sh"

echo "== Resolving images from compose.yaml + .env.example"
# The Grafana password is required by compose.yaml; a placeholder is enough here.
mapfile -t IMAGES < <(
  GRAFANA_ADMIN_PASSWORD=placeholder \
    docker compose --env-file .env.example config --images | tr -d '\r' | sort -u
)
printf '   %s\n' "${IMAGES[@]}"

if [[ "${SKIP_PULL:-0}" != 1 ]]; then
  echo "== Pulling images"
  for img in "${IMAGES[@]}"; do docker pull -q "$img"; done
fi

echo "== Recording image IDs"
for img in "${IMAGES[@]}"; do
  # Separate assignment so set -e stops the script if an image is missing.
  id="$(docker image inspect --format '{{.Id}}' "$img")"
  printf '%s %s\n' "$img" "$id"
done > "$STAGE/images/manifest.txt"

echo "== Saving images (this takes a while)"
docker save "${IMAGES[@]}" | gzip > "$STAGE/images/images.tar.gz"

if [[ -d vendor ]] && [[ -n "$(ls -A vendor)" ]]; then
  echo "== Adding vendor/ files"
  cp -r vendor "$STAGE/vendor"
fi

echo "== Writing checksums"
# Written outside the folder first, so the checksum file never lists itself.
(cd "$STAGE" && find . -type f | sort | xargs sha256sum) > "$STAGE.sums"
mv "$STAGE.sums" "$STAGE/SHA256SUMS"

echo "== Packing"
tar -cf "dist/$NAME.tar" -C dist "$NAME"
(cd dist && sha256sum "$NAME.tar" > "$NAME.tar.sha256")
rm -rf "$STAGE"

echo
echo "Bundle ready:"
ls -lh "dist/$NAME.tar" "dist/$NAME.tar.sha256"