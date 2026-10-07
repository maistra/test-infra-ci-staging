#!/bin/bash

set -euo pipefail

# --- STAGING ONLY: resource monitoring (do NOT migrate to production) ---
METRICS_LOG="/tmp/resource-metrics.log"
(
  echo "=== SYSTEM INFO ==="
  echo "CPUs: $(nproc)"
  lscpu | grep -E 'Model name|CPU\(s\)|Thread'
  free -h
  df -h /
  echo "=== SAMPLING EVERY 10s ==="
  while true; do
    printf '%s | mem: %s | disk: %s | load: %s\n' \
      "$(date +%H:%M:%S)" \
      "$(free -h | awk '/Mem:/{print $3"/"$2}')" \
      "$(df -h / | awk 'NR==2{print $3"/"$2}')" \
      "$(cut -d' ' -f1-3 /proc/loadavg)"
    sleep 10
  done
) > "$METRICS_LOG" 2>&1 &
METRICS_PID=$!
# --- END STAGING ONLY ---

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
make "build-containers-${VERSION}"
echo "Build validation passed for maistra-builder:${VERSION}"

# --- STAGING ONLY: print resource summary (do NOT migrate to production) ---
kill "$METRICS_PID" 2>/dev/null || true
wait "$METRICS_PID" 2>/dev/null || true
echo ""
echo "=== RESOURCE USAGE LOG ==="
cat "$METRICS_LOG"
# --- END STAGING ONLY ---
