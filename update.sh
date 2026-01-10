#!/usr/bin/env bash
set -euo pipefail

# update.sh
# Safely overwrite this repository with the remote branch state.
# Usage: ./update.sh [remote]
# - Defaults to remote 'origin'.
# Behavior:
# 1. Creates a local backup branch named backup-before-update-<timestamp>.
# 2. Fetches the remote and resets --hard to remote/current-branch.
# 3. Removes untracked files (git clean -fdx).

repo_root="$(cd "$(dirname "$0")" && pwd)"
cd "$repo_root"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not a git repository: $repo_root" >&2
  exit 1
fi

remote="${1:-origin}"
branch="$(git rev-parse --abbrev-ref HEAD)"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_branch="backup-before-update-$timestamp"

echo "Repository: $repo_root"
echo "Current branch: $branch"
echo "Remote: $remote"
echo "Creating backup branch: $backup_branch"
git branch --force "$backup_branch" || git branch "$backup_branch"

echo "Fetching from $remote..."
git fetch --prune "$remote"

if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
  echo "Resetting local $branch to $remote/$branch (this will discard local commits not on remote)"
  git reset --hard "$remote/$branch"

  echo "Removing untracked files, including ignored ones (git clean -fdx)"
  git clean -fdx

  echo "Updating submodules (if any)"
  git submodule sync --recursive 2>/dev/null || true
  git submodule update --init --recursive 2>/dev/null || true

  echo "Update complete. Local branch '$branch' now matches '$remote/$branch'."
  echo "Backup of previous HEAD is on branch: $backup_branch"
else
  echo "Error: remote branch '$remote/$branch' not found. Aborting." >&2
  exit 2
fi

exit 0
