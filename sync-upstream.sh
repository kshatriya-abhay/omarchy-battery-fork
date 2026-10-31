#!/bin/bash

# Brings changes to the stock omarchy.power plugin into this fork.
#
# 1. On `upstream`, replace the files with the installed stock plugin and
#    commit "sync with upstream omarchy <version>" if anything changed.
# 2. Cherry-pick that commit onto `main`.
# 3. On success: copy the plugin into place and restart the shell. With
#    --push, or `git config sync-upstream.push true` in this repo (for hooks,
#    which pass no arguments), also push both branches to origin.
#    On a conflict: abort, put `upstream` back so the next run tries again, and
#    print how to resolve it by hand.
#
# Always exits 0, so it can run from an `omarchy update` hook.
# STOCK_DIR and PLUGIN_DIR can be overridden, for testing.

REPO_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
STOCK_DIR=${STOCK_DIR:-/usr/share/omarchy/shell/plugins/panels/power}
PLUGIN_DIR=${PLUGIN_DIR:-$HOME/.config/omarchy/plugins/abhay.power}

git() { command git -C "$REPO_DIR" "$@"; }

push=false
[[ ${1:-} == --push || $(git config --bool sync-upstream.push) == true ]] && push=true

echo -e "\e[32m\nSync omarchy.power fork\e[0m"

stop() {
  echo "sync-upstream: $*" >&2
  exit 0
}

[[ -d $STOCK_DIR ]] || stop "stock plugin not found: $STOCK_DIR"
[[ $(git symbolic-ref --short HEAD 2>/dev/null) == main ]] || stop "check out main first; skipping"
[[ -z $(git status --porcelain) ]] || stop "uncommitted changes in $REPO_DIR; skipping"

version=$(pacman -Q omarchy 2>/dev/null | cut -d' ' -f2)
message="sync with upstream omarchy ${version:-unknown}"

# --- 1. Commit the installed stock files on upstream ---
git checkout -q upstream || stop "couldn't check out upstream"
# Replace only tracked files, so a file upstream deleted goes away too.
git ls-files -z | (cd "$REPO_DIR" && xargs -0 rm -f)
cp -a "$STOCK_DIR/." "$REPO_DIR/"
git add -A

if git diff --cached --quiet; then
  git checkout -q main
  echo "omarchy.power is unchanged in omarchy ${version:-unknown}. Nothing to sync."
  exit 0
fi

echo "omarchy.power changed in omarchy ${version:-unknown}:"
git diff --cached --stat
git commit -qm "$message"
commit=$(git rev-parse HEAD)
git checkout -q main

# --- 2. Cherry-pick onto main ---
if ! git cherry-pick "$commit"; then
  git cherry-pick --abort
  # Undo the upstream commit too, or the next run would see no difference and
  # never retry.
  git update-ref refs/heads/upstream "$commit~1"
  echo >&2
  echo "Merge conflict: '$message' didn't apply cleanly to main. Nothing was changed." >&2
  echo "Resolve by hand in $REPO_DIR:" >&2
  echo "  git branch -f upstream $commit" >&2
  echo "  git cherry-pick $commit    # fix the conflicts, then: git cherry-pick --continue" >&2
  exit 0
fi
echo "Applied to main: $message"

# --- 3. Install, restart, push ---
rsync -a --delete --exclude .git --exclude CLAUDE.md --exclude sync-upstream.sh \
  "$REPO_DIR/" "$PLUGIN_DIR/"
echo "Copied to $PLUGIN_DIR"

omarchy restart shell && echo "Restarted the Omarchy shell"

if ! $push; then
  echo "Not pushing (use --push, or: git -C $REPO_DIR config sync-upstream.push true)"
elif git remote get-url origin >/dev/null 2>&1; then
  git push -q origin main upstream && echo "Pushed main and upstream to origin" ||
    echo "sync-upstream: push failed; run 'git push origin main upstream' later" >&2
else
  echo "No origin remote; skipped the push"
fi
exit 0
