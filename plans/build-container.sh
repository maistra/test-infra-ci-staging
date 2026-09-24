#!/bin/bash

set -euo pipefail

DISK_INITIAL="$(df -h)"
trap 'echo "---Disk usage (initial) ---"; echo "$DISK_INITIAL"; echo "--- Disk usage (at failure) ---"; df -h' ERR

VERSION="${BUILDER_VERSION:?BUILDER_VERSION must be set}"
SOURCE_REPO="${SOURCE_REPO:?SOUCE_REPO must be set}"
SOURCE_REF="${SOURCE_REF:?SOUCE_REF must be set}"

git clone "${SOURCE_REPO}" /tmp/pr-source
git -C /tmp/pr-source checkout "${SOURCE_REF}"

cp -r /tmp/pr-source/docker ./docker
cp /tmp/pr-source/Makefile ./Makefile

export CONTAINER_CLI=docker
export HUB=quay.io/maistra-dev

make "build-containers-${VERSION}"
echo "Build validation passed for maistra-builder:${VERSION}"
