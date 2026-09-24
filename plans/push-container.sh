#!/bin/bash
set -euo pipefail

DISK_INITIAL="$(df -h)"
trap 'echo "--- Disk usage (initial) ---"; echo "$DISK_INITIAL"; echo "--- Disk usage (at failure) ---"; df -h' ERR

VERSION="${BUILDER_VERSION:?BUILDER_VERSION must be set}"
QUAY_USER="${QUAY_USER:?QUAY_USER must be set}"
QUAY_PASS="${QUAY_PASS:?QUAY_PASS must be set}"
PUSH_MODE="${PUSH_MODE:?PUSH_MODE must be set (single or multi)}"

export CONTAINER_CLI=docker
export HUB=quay.io/maistra-dev

docker login -u="${QUAY_USER}" -p="$QUAY_PASS" quay.io

if [ "${USE_STAGING_TAGS:-false}" = "true" ]; then
    STAGING_SUFFIX="-staging"
else
    STAGING_SUFFIX=""
fi

PUSHED_TAGS=()

if [ "$PUSH_MODE" = "single" ]; then
    make "maistra-builder_${VERSION}"
    TAG="${VERSION}${STAGING_SUFFIX}"
    docker tag "${HUB}/maistra-builder:${VERSION}" "${HUB}/maistra-builder:${TAG}"
    docker push "${HUB}/maistra-builder:${TAG}"
    PUSHED_TAGS+=("${TAG}")
elif [ "$PUSH_MODE" = "multi" ]; then
    ARCH=$(uname -m)
    make "maistra-builder_${VERSION}"
    TAG="${VERSION}${STAGING_SUFFIX}-${ARCH}"
    docker tag "${HUB}/maistra-builder:${VERSION}" "${HUB}/maistra-builder:${TAG}"
    docker push "${HUB}/maistra-builder:${TAG}"
    PUSHED_TAGS+=("${TAG}")
else
    echo "ERROR: unknown PUSH_MODE: ${PUSH_MODE}" >&2
    exit 1
fi

# --- STAGING ONLY: remove this block when migrating to production ---
# Set 7-day expiration on staging tags to avoid accumulating images
# that consume the shared quay.io/maistra-dev storage quota.
if [ "${USE_STAGING_TAGS:-false}" = "true" ]; then
  EXPIRATION=$(date -d "+7 days" +%s)
  for TAG in "${PUSHED_TAGS[@]}"; do
    curl -sf -X PUT \
      "https://quay.io/api/v1/repository/maistra-dev/maistra-builder/tag/${TAG}" \
      -u "${QUAY_USER}:${QUAY_PASS}" \
      -H "Content-Type: application/json" \
      -d "{\"expiration\": ${EXPIRATION}}" \
      && echo "Tag ${TAG}: expiration set to 7 days" \
      || echo "WARNING: failed to set expiration on tag ${TAG} (non-blocking)"
  done
fi
# --- END STAGING ONLY ---

echo "Push completed for maistra-builder:${VERSION}${STAGING_SUFFIX} (mode: ${PUSH_MODE})"
