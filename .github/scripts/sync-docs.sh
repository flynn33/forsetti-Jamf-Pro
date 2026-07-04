#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"

for file in "$REPO_ROOT/README.md" "$REPO_ROOT/WIKI.md"; do
  [[ -f "$file" ]] || continue
  if grep -q "Current release:" "$file"; then
    sed -i '' "s/Current release:.*/Current release: \`v${VERSION}\`/" "$file"
  fi
done

echo "docs_synced=true"
