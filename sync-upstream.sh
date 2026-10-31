#!/bin/bash

# Brings changes to the stock omarchy.power plugin into this fork.
#
# Compares the `upstream` branch with the omarchy.power files installed on the
# system. If they differ, it commits the installed files on top of `upstream`
# and merges that into `main` as "sync with upstream omarchy <version>". On a
# clean merge it moves `upstream` forward, copies the plugin into place and
# restarts the shell. On a conflict it prints the conflicting files, aborts the
# merge (leaving both branches and the working tree as they were) and still
# exits 0, so it is safe to run from an `omarchy update` hook.
#
# STOCK_DIR and PLUGIN_DIR can be overridden, for testing.

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STOCK_DIR=${STOCK_DIR:-/usr/share/omarchy/shell/plugins/panels/power}
PLUGIN_DIR=${PLUGIN_DIR:-$HOME/.config/omarchy/plugins/abhay.power}

fail() {
  echo "sync-upstream: $*" >&2
  exit 1
}

git() { command git -C "$REPO_DIR" "$@"; }

[[ -d $STOCK_DIR ]] || fail "stock plugin not found: $STOCK_DIR"
[[ $(git symbolic-ref --short HEAD 2>/dev/null) == main ]] || fail "check out main first"
[[ -z $(git status --porcelain) ]] || fail "working tree has uncommitted changes"

version=$(pacman -Q omarchy 2>/dev/null | cut -d' ' -f2)
version=${version:-unknown}

# Snapshot the installed files as a git tree, without touching the working
# tree or the real index.
tmp_index=$(mktemp)
trap 'rm -f "$tmp_index"' EXIT
rm -f "$tmp_index"
stock_tree=$(GIT_INDEX_FILE=$tmp_index git --work-tree="$STOCK_DIR" add -A . &&
  GIT_INDEX_FILE=$tmp_index git write-tree)

if [[ $stock_tree == $(git rev-parse 'upstream^{tree}') ]]; then
  echo "omarchy.power is unchanged in omarchy $version. Nothing to sync."
  exit 0
fi

echo "omarchy.power changed in omarchy $version:"
git diff --stat upstream "$stock_tree"

stock_commit=$(git commit-tree "$stock_tree" -p upstream -m "omarchy.power from omarchy $version")

if merge_output=$(git merge --no-ff --no-edit -m "sync with upstream omarchy $version" "$stock_commit" 2>&1); then
  git update-ref refs/heads/upstream "$stock_commit"
  echo "Merged into main: sync with upstream omarchy $version"

  rsync -a --delete --exclude .git --exclude CLAUDE.md --exclude sync-upstream.sh \
    "$REPO_DIR/" "$PLUGIN_DIR/"
  echo "Copied to $PLUGIN_DIR"

  omarchy restart shell
  echo "Restarted the Omarchy shell"
else
  echo "$merge_output" >&2
  echo >&2
  echo "Merge conflict syncing with upstream omarchy $version, in:" >&2
  git diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  git merge --abort
  echo "Merge aborted; the repo is unchanged. Resolve by hand with:" >&2
  echo "  git -C $REPO_DIR merge $stock_commit" >&2
fi
