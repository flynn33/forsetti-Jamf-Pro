#!/usr/bin/env bash
set -euo pipefail

# sync-docs.sh — Syncs version strings in README.md and WIKI.md to match VERSION file
# Also validates that all modules are documented

REPO_ROOT="$(git rev-parse --show-toplevel)"
VERSION_FILE="$REPO_ROOT/VERSION"
README="$REPO_ROOT/README.md"
WIKI="$REPO_ROOT/WIKI.md"
MODULES_DIR="$REPO_ROOT/JamfDashboardApp/Modules"

VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
CHANGES_MADE=false
ISSUES=()

echo "Syncing documentation to version ${VERSION}..."

# ── Update README.md version line ──
if [ -f "$README" ]; then
  # Match the existing format: Current release: `3` (`CURRENT_PROJECT_VERSION = 3`)
  if grep -q "Current release:" "$README"; then
    sed -i '' "s/Current release: \`[^\`]*\`.*/Current release: \`v${VERSION}\`/" "$README"
    CHANGES_MADE=true
    echo "Updated README.md version to v${VERSION}"
  fi
fi

# ── Update WIKI.md version lines ──
if [ -f "$WIKI" ]; then
  if grep -q "CURRENT_PROJECT_VERSION" "$WIKI"; then
    sed -i '' "s/\`CURRENT_PROJECT_VERSION = [^\`]*\`/\`CURRENT_PROJECT_VERSION = ${VERSION}\`/" "$WIKI"
    sed -i '' "s/\`MARKETING_VERSION = [^\`]*\`/\`MARKETING_VERSION = ${VERSION}\`/" "$WIKI"
    CHANGES_MADE=true
    echo "Updated WIKI.md version to ${VERSION}"
  fi
fi

# ── Validate module documentation coverage ──
if [ -d "$MODULES_DIR" ]; then
  for module_dir in "$MODULES_DIR"/*/; do
    module_name=$(basename "$module_dir")
    # Check if module is mentioned in README
    if [ -f "$README" ] && ! grep -qi "$module_name" "$README"; then
      ISSUES+=("README.md is missing documentation for module: $module_name")
    fi
    # Check if module is mentioned in WIKI
    if [ -f "$WIKI" ] && ! grep -qi "$module_name" "$WIKI"; then
      ISSUES+=("WIKI.md is missing documentation for module: $module_name")
    fi
  done
fi

# ── Report results ──
if [ "$CHANGES_MADE" = true ]; then
  echo "changes_made=true"
else
  echo "changes_made=false"
fi

if [ ${#ISSUES[@]} -gt 0 ]; then
  echo ""
  echo "Documentation issues found:"
  for issue in "${ISSUES[@]}"; do
    echo "  - $issue"
  done
  echo "issues_found=true"
  # Output issues for GitHub issue creation
  ISSUE_BODY=""
  for issue in "${ISSUES[@]}"; do
    ISSUE_BODY="${ISSUE_BODY}- ${issue}\n"
  done
  echo "issue_body<<EOF"
  printf "%b" "$ISSUE_BODY"
  echo "EOF"
else
  echo "issues_found=false"
  echo "All modules are documented."
fi
