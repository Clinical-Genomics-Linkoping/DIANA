#!/usr/bin/env bash
set -euo pipefail

# Always run from repo root (directory of this script)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

UPSTREAM_URL="https://github.com/VilhelmMagnusLab/DIANA.git"

# Also treat as ZIP install if .git exists but has no commits (incomplete previous init)
if [ ! -d .git ] || ! git rev-parse HEAD >/dev/null 2>&1; then
  echo "[update] No git repository found (ZIP install detected)."

  # Back up user config files before git takes over
  BACKUP_DIR="conf/backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  backed_up=0
  for cfg in conf/annotation.config conf/epi2me.config conf/example.config; do
    if [ -f "$cfg" ]; then
      cp "$cfg" "$BACKUP_DIR/$(basename $cfg)"
      backed_up=1
    fi
  done
  if [ "$backed_up" -eq 1 ]; then
    echo "[update] Config files backed up to $BACKUP_DIR"
    echo "[update] After update, re-apply your custom paths from those backups."
  fi

  echo "[update] Initializing git and connecting to $UPSTREAM_URL ..."
  git init -q
  git remote add origin "$UPSTREAM_URL" 2>/dev/null || git remote set-url origin "$UPSTREAM_URL"
  git fetch origin --depth=1 -q

  # Use reset instead of checkout to avoid "would be overwritten" errors
  git checkout -q -b main --track origin/main 2>/dev/null || {
    git reset --hard origin/main -q
  }

  echo "[update] Done. Repository initialized. Future updates will be fast."
  echo "[update] Current commit: $(git rev-parse --short HEAD)"
  if [ "$backed_up" -eq 1 ]; then
    echo "[update] Remember to restore your settings from: $BACKUP_DIR"
  fi
  exit 0
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"

# Use 'upstream' if it exists, otherwise fall back to 'origin'
if git remote get-url upstream >/dev/null 2>&1; then
  FETCH_REMOTE="upstream"
  existing_url="$(git remote get-url upstream)"
  if [ "$existing_url" != "$UPSTREAM_URL" ]; then
    echo "[update] Updating upstream remote to $UPSTREAM_URL"
    git remote set-url upstream "$UPSTREAM_URL"
  fi
else
  FETCH_REMOTE="origin"
fi

echo "[update] Fetching latest changes from $FETCH_REMOTE (shallow fetch for speed)..."
git fetch "$FETCH_REMOTE" --depth=1 --tags --prune

# Detect default branch (fallback to main)
upstream_default_branch="$(git symbolic-ref -q --short refs/remotes/${FETCH_REMOTE}/HEAD 2>/dev/null | cut -d'/' -f2 || true)"
if [ -z "${upstream_default_branch:-}" ]; then
  upstream_default_branch="main"
fi

stashed=0
if ! git diff-index --quiet HEAD --; then
  # Back up config files before stashing, in case stash pop has conflicts
  BACKUP_DIR="conf/backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  backed_up=0
  for cfg in conf/annotation.config conf/epi2me.config conf/example.config; do
    if [ -f "$cfg" ] && ! git diff --quiet HEAD -- "$cfg" 2>/dev/null; then
      cp "$cfg" "$BACKUP_DIR/$(basename $cfg)"
      backed_up=1
    fi
  done
  if [ "$backed_up" -eq 1 ]; then
    echo "[update] Modified config files backed up to $BACKUP_DIR"
  fi

  stashed=1
  msg="auto-update-$(date +%Y%m%d_%H%M%S)"
  echo "[update] Local changes detected. Stashing (name: $msg)..."
  git stash push -u -m "$msg" >/dev/null
fi

echo "[update] Pulling latest changes from '$FETCH_REMOTE/$upstream_default_branch'..."
if ! git pull --ff-only "$FETCH_REMOTE" "$upstream_default_branch" 2>/dev/null; then
  echo "[update] Fast-forward not possible (branches diverged). Resetting to remote..."
  git reset --hard "${FETCH_REMOTE}/${upstream_default_branch}"
fi

if [ "$stashed" -eq 1 ]; then
  echo "[update] Restoring stashed changes..."
  set +e
  git stash pop
  pop_rc=$?
  set -e
  if [ $pop_rc -ne 0 ]; then
    echo "[update] Stash pop reported conflicts. Please resolve and commit:" >&2
    echo "        git status" >&2
    exit 2
  fi
fi

echo "[update] Update complete. Current commit: $(git rev-parse --short HEAD)"
if [ -x ./validate_setup.sh ]; then
  echo "[update] Tip: run ./validate_setup.sh to verify containers and tooling."
fi


