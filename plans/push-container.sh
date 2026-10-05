#!/bin/bash
set -euo pipefail

DISK_INITIAL="$(df -h)"
trap 'echo "--- Disk usage (initial) ---"; echo "$DISK_INITIAL"; echo "--- Disk usage (at failure) ---"; df -h' ERR

VERSION="${BUILDER_VERSION:?BUILDER_VERSION must be set}"
QUAY_USER="${QUAY_USER:?QUAY_USER must be set}"
QUAY_PASS="${QUAY_PASS:?QUAY_PASS must be set}"
PUSH_MODE="${PUSH_MODE:?PUSH_MODE must be set (single or multi)}"

# TMT clones the repo (git_url + git_ref from the workflow) and makes it
# available at TMT_TREE. The script runs from a different directory by default,
# so we cd to TMT_TREE where the Makefile and docker/ directory live.
# See: https://tmt.readthedocs.io/en/stable/overview.html (Step Variables)
ROOT_REPO="${TMT_TREE:?TMT_TREE must be set by TMT}"

export CONTAINER_CLI=docker
export HUB=quay.io/maistra-dev

# Debug: print the directory TMT launched us from (to verify our assumption
# that it's NOT the repo root). Remove this once confirmed.
echo "DEBUG: initial working directory is $(pwd)"
echo "DEBUG: TMT_TREE is ${TMT_TREE:-NOT SET}"
echo "DEBUG: ROOT_REPO is ${ROOT_REPO:-NOT SET}"



if [ "${USE_STAGING_TAGS:-false}" = "true" ]; then
    STAGING_SUFFIX="-staging"
else
    STAGING_SUFFIX=""
fi

# Build the tag based on push mode:
#   single: just version + staging suffix (e.g. "3.5-staging")
#   multi:  version + staging suffix + arch (e.g. "3.5-staging-x86_64")
if [ "$PUSH_MODE" = "single" ]; then
    TAG="${VERSION}${STAGING_SUFFIX}"
elif [ "$PUSH_MODE" = "multi" ]; then
    ARCH=$(uname -m)
    TAG="${VERSION}${STAGING_SUFFIX}-${ARCH}"
else
    echo "ERROR: unknown PUSH_MODE: ${PUSH_MODE}" >&2
    exit 1
fi

docker login -u="${QUAY_USER}" -p="$QUAY_PASS" quay.io

cd "${ROOT_REPO}"
make "maistra-builder_${VERSION}"
docker tag "${HUB}/maistra-builder:${VERSION}" "${HUB}/maistra-builder:${TAG}"
docker push "${HUB}/maistra-builder:${TAG}"

# --- STAGING ONLY: remove this block when migrating to production ---
# Set 7-day expiration on staging tags to avoid accumulating images
# that consume the shared quay.io/maistra-dev storage quota.
if [ "${USE_STAGING_TAGS:-false}" = "true" ]; then
  EXPIRATION=$(date -d "+7 days" +%s)
  curl -sf -X PUT \
    "https://quay.io/api/v1/repository/maistra-dev/maistra-builder/tag/${TAG}" \
    -u "${QUAY_USER}:${QUAY_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"expiration\": ${EXPIRATION}}" \
    && echo "Tag ${TAG}: expiration set to 7 days" \
    || echo "WARNING: failed to set expiration on tag ${TAG} (non-blocking)"
fi
# --- END STAGING ONLY ---

echo "Push completed for maistra-builder:${TAG} (mode: ${PUSH_MODE})"
