#!/bin/bash
#
# Sync staging repo with the upstream (production) repo.
#
# The staging repo (maistra/test-infra-ci-staging) is a copy of
# maistra/test-infra with CI-specific modifications on top 
# These modifications live as commits on top of the upstream history.
#
# This script rebases those staging-specific commits onto the latest
# upstream tip, so that after sync the branch looks like:
#
#   upstream history (identical to production) + staging patches on top
#
# Git identifies the staging commits automatically: they are the commits
# present in main but not in upstream/main. No hardcoded list.
#
# The script does NOT push. After running, review the result and push
# manually with --force-with-lease.

set -euo pipefail

UPSTREAM_REMOTE="upstream"
BRANCH="main"

usage() {
  cat <<'EOF'
Usage:
  sync-from-upstream.sh [--dry-run]
  sync-from-upstream.sh -h | --help

Options:
  --dry-run   Show what would change without modifying anything.
  -h, --help  Show this help message and exit.

What it does:
  1. Fetches the latest state from the upstream remote.
  2. Rebases the staging-specific commits on top of the new upstream tip.
     If there are no new upstream commits, the branch is skipped.
  3. If a rebase conflict occurs, the script stops. Resolve the conflict
     manually (git rebase --continue) or abort (git rebase --abort).

After running:
  Review the result before pushing:
    git log upstream/main..main     # staging-only commits
    git diff upstream/main..main    # staging-only changes

  Push (after review):
    git push origin main --force-with-lease

  --force-with-lease is needed because rebase rewrites the staging commits
  (new SHAs). It is safe because nobody else works on the staging repo,
  and --force-with-lease protects against accidental concurrent pushes.

Examples:
  # Preview what would happen
  ./.github/scripts/sync-from-upstream.sh --dry-run

  # Sync for real
  ./.github/scripts/sync-from-upstream.sh
EOF
}

DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "Error: unknown argument '$arg'"
      echo ""
      usage
      exit 1
      ;;
  esac
done

# Verify we're on the right branch
CURRENT=$(git branch --show-current)
if [[ "$CURRENT" != "$BRANCH" ]]; then
  echo "Error: expected branch '$BRANCH', got '$CURRENT'"
  exit 1
fi

# Verify the upstream remote exists
if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
  echo "Error: remote '$UPSTREAM_REMOTE' not found."
  echo "Add it with: git remote add $UPSTREAM_REMOTE https://github.com/maistra/test-infra.git"
  exit 1
fi

echo "Fetching upstream..."
git fetch "$UPSTREAM_REMOTE"

echo ""
echo "============================================"
echo "  $BRANCH"
echo "============================================"

STAGING_COMMITS=$(git log --oneline "$UPSTREAM_REMOTE/$BRANCH..$BRANCH" 2>/dev/null)
STAGING_COUNT=$(echo "$STAGING_COMMITS" | grep -c . 2>/dev/null || echo 0)

BEHIND=$(git rev-list --count "$BRANCH..$UPSTREAM_REMOTE/$BRANCH" 2>/dev/null || echo 0)

echo "  Staging commits on top: $STAGING_COUNT"
if [[ -n "$STAGING_COMMITS" ]]; then
  while IFS= read -r line; do echo "    $line"; done <<< "$STAGING_COMMITS"
fi
echo "  Commits behind upstream: $BEHIND"

if [[ "$BEHIND" -eq 0 ]]; then
  echo "  Already up to date."
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "  [dry-run] Would rebase $STAGING_COUNT staging commit(s) onto $UPSTREAM_REMOTE/$BRANCH"
  exit 0
fi

if ! git rebase "$UPSTREAM_REMOTE/$BRANCH"; then
  echo ""
  echo "  CONFLICT during rebase."
  echo "  Resolve conflicts, then: git rebase --continue"
  echo "  Or abort with: git rebase --abort"
  exit 1
fi

echo ""
echo "============================================"
echo "  Done."
echo "============================================"
echo ""
echo "Staging commits after rebase:"
git log --oneline "$UPSTREAM_REMOTE/$BRANCH..$BRANCH" | sed 's/^/  /'
echo ""
echo "Files modified by staging (should only be CI files):"
git diff --stat "$UPSTREAM_REMOTE/$BRANCH..$BRANCH" | sed 's/^/  /'
echo ""
echo "Review:"
echo "  git log upstream/$BRANCH..$BRANCH     # staging-only commits"
echo "  git diff upstream/$BRANCH..$BRANCH    # staging-only changes"
echo ""
echo "Push (after review):"
echo "  git push origin $BRANCH --force-with-lease"