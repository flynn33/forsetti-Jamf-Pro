#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BUMP_TYPE="${1:-patch}"
case "$BUMP_TYPE" in
  major|minor|patch) ;;
  *) echo "Usage: release.sh major|minor|patch" >&2; exit 1 ;;
esac

.github/scripts/bump-version.sh --type "$BUMP_TYPE"
.github/scripts/generate-changelog.sh
.github/scripts/sync-docs.sh

git add VERSION CHANGELOG.md README.md WIKI.md Forsetti.xcodeproj/project.pbxproj
git commit -m "chore: release $(tr -d '[:space:]' < VERSION)"
