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

cd "${ROOT_REPO}"

docker login -u="${QUAY_USER}" -p="${QUAY_PASS}" quay.io

# Use the same Makefile targets as Prow:
#   single-arch (2.3, 2.4): make maistra-builder_VERSION.push
#   multi-arch  (2.5+):     make maistra-builder_VERSION.push_multi
# The Makefile appends TAG_SUFFIX (env var from the workflow) to the tag.
if [ "$PUSH_MODE" = "single" ]; then
  make "maistra-builder_${VERSION}.push"
elif [ "$PUSH_MODE" = "multi" ]; then
  make "maistra-builder_${VERSION}.push_multi"
else
  echo "ERROR: unknown PUSH_MODE: ${PUSH_MODE}" >&2
  exit 1
fi

echo "Push completed for maistra-builder:${VERSION} (mode: ${PUSH_MODE})"
