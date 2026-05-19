#!/usr/bin/env bash
# Usage: bash release.sh
# Bumps the patch version, commits, tags, and pushes to all remotes.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="nextflow.config"

# Read current version
current=$(grep -oP "version\s*=\s*'\K[0-9]+\.[0-9]+\.[0-9]+" "$CONFIG")
if [ -z "$current" ]; then
  echo "[release] Could not find version in $CONFIG — aborting." >&2
  exit 1
fi

# Increment patch
IFS='.' read -r major minor patch <<< "$current"
patch=$(( patch + 1 ))
new_version="${major}.${minor}.${patch}"

echo "[release] Bumping version: ${current} → ${new_version}"

# Update nextflow.config
sed -i "s/version\s*=\s*'${current}'/version         = '${new_version}'/" "$CONFIG"

# Commit and tag
git add "$CONFIG"
git commit -m "chore: bump version to ${new_version}" --no-verify
git tag -a "v${new_version}" -m "Version ${new_version}"

echo "[release] Tagged v${new_version}"

# Push branch + tags to all remotes
for remote in $(git remote); do
  echo "[release] Pushing to ${remote}..."
  git push --no-verify "$remote" HEAD --follow-tags
done

echo "[release] Done. Version ${new_version} is live on all remotes."
