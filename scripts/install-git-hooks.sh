#!/usr/bin/env bash
# scripts/install-git-hooks.sh — point git at .githooks/ for project-tracked hooks.
#
# Idempotent. Run once after `git clone` (or as part of `mix setup`).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if [[ ! -d ".githooks" ]]; then
  echo "install-git-hooks: .githooks/ directory not found" >&2
  exit 1
fi

# Make every file in .githooks/ executable
chmod +x .githooks/* 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true

git config core.hooksPath .githooks
echo "install-git-hooks: core.hooksPath set to .githooks/"
echo "install-git-hooks: hooks installed:"
ls -l .githooks/ | tail -n +2 | awk '{print "  " $NF}'
