#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
TODAY="$(date +%Y-%m-%d)"

if ! grep -q "^## \\[Unreleased\\]" "$CHANGELOG"; then
  {
    echo "# Changelog"
    echo
    echo "## [Unreleased]"
    echo
    echo "---"
  } > "$CHANGELOG"
fi

if ! grep -q "^## \\[$VERSION\\]" "$CHANGELOG"; then
  tmp="$(mktemp)"
  awk -v version="$VERSION" -v today="$TODAY" '
    /^---$/ && !inserted {
      print "---"
      print ""
      print "## [" version "] - " today
      print ""
      print "- Release notes pending owner review."
      print ""
      inserted = 1
      next
    }
    { print }
  ' "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
fi

echo "changelog_version=$VERSION"
