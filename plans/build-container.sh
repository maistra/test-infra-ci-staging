#!/bin/bash

set -euo pipefail

DISK_INITIAL="$(df -h)"
trap 'echo "---Disk usage (initial) ---"; echo "$DISK_INITIAL"; echo "--- Disk usage (at failure) ---"; df -h' ERR

VERSION="${BUILDER_VERSION:?BUILDER_VERSION must be set}"
SOURCE_REPO="${SOURCE_REPO:?SOURCE_REPO must be set}"
SOURCE_REF="${SOURCE_REF:?SOURCE_REF must be set}"

export CONTAINER_CLI=docker
export HUB=quay.io/maistra-dev

# Clone the PR source repo and check out the exact commit to build.
# SOURCE_REPO is the clone URL of the PR head repo (could be a fork).
# SOURCE_REF is the PR head SHA.
git clone "${SOURCE_REPO}" /tmp/source
cd /tmp/source
git checkout "${SOURCE_REF}"
# Step 1: build the image (Makefile target maistra-builder_VERSION)
make "maistra-builder_${VERSION}"
echo "Image built: maistra-builder:${VERSION}"

# Step 2: self-test DinD (same as Makefile target build-containers-VERSION,
# but with a volume mount to capture dockerd.log for debugging).
# The entrypoint starts dockerd and writes its log to ${ARTIFACTS}/dockerd.log.
# By mounting a host directory and setting ARTIFACTS, we can read the log
# even if dockerd never starts and the container is killed.
# Run detached and wait 30s: enough for dockerd to either start or fail.
mkdir -p /tmp/docker-debug
docker run -d --name dind-selftest --privileged \
  -v "${PWD}:/work" --workdir /work \
  -v /var/lib/docker \
  -v /tmp/docker-debug:/debug \
  -e ARTIFACTS=/debug \
  --entrypoint entrypoint \
  "${HUB}/maistra-builder:${VERSION}" \
  make "maistra-builder_${VERSION}"

sleep 30

echo "=== dockerd.log ==="
cat /tmp/docker-debug/dockerd.log 2>/dev/null || echo "(no dockerd.log found)"
echo "=== end dockerd.log ==="

docker stop dind-selftest 2>/dev/null || true
docker rm dind-selftest 2>/dev/null || true
exit 1
