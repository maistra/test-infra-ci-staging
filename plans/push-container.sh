#!/bin/bash
set -euo pipefail

# --- STAGING ONLY: resource monitoring (do NOT migrate to production) ---
# Write metrics to TMT_TEST_DATA so they appear as a downloadable artifact,
# not mixed into the test stdout (which buildx floods with output).
METRICS_LOG="${TMT_TEST_DATA:-/tmp}/resource-metrics.log"
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

echo "${QUAY_PASS}" | docker login -u="${QUAY_USER}" --password-stdin quay.io

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

# --- STAGING ONLY: stop resource monitoring (do NOT migrate to production) ---
kill "$METRICS_PID" 2>/dev/null || true
wait "$METRICS_PID" 2>/dev/null || true
echo "Resource metrics saved to: ${METRICS_LOG}"
# --- END STAGING ONLY ---
