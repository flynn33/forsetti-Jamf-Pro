#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh — Automated, branch-driven version bump.
#
# Detects whether the current change is a patch or a feature from the branch
# prefix and bumps the version exactly once per branch:
#
#     fix/*      → patch    (3.25.5 → 3.25.6)   third component
#     feature/*  → feature  (3.25.5 → 3.26.0)   second component, fixes reset
#     (anything else, incl. main / detached HEAD) → no auto-bump
#
# Version scheme is framework.feature.fixes. Framework (major) bumps stay
# MANUAL — this script never touches the first component.
#
# Idempotent: it only acts while the working-tree VERSION still equals the
# baseline (main's VERSION). After one bump, VERSION differs from main, so
# re-runs are no-ops. This also auto-resolves collisions — if main later
# advances to the number this branch picked, the next run bumps to the next
# free number.
#
# What it updates (targeted token replacements — narratives are preserved):
#   • VERSION
#   • Forsetti Jamf Pro.xcodeproj/project.pbxproj  (every MARKETING_VERSION and
#     CURRENT_PROJECT_VERSION field)
#   • README.md   (only the leading `Current release: \`vX.Y.Z\`` token)
#   • WIKI.md     (only the CURRENT_PROJECT_VERSION / MARKETING_VERSION lines)
#   • CHANGELOG.md (inserts a dated stub section under "## [Unreleased]")
#
# NOTE: it intentionally does NOT call .github/scripts/sync-docs.sh — that
# script's README rule rewrites the whole "Current release:" line and would
# wipe the narrative. The targeted replacements here keep the prose intact.
# The release narrative (README description, CHANGELOG body) is still authored
# by hand — this only advances the numbers.
#
# Usage:
#   bash scripts/bump-version.sh            # apply the bump (no staging)
#   bash scripts/bump-version.sh --stage    # apply + git-add (used by pre-commit)
#   bash scripts/bump-version.sh --dry-run  # print what would change, touch nothing
#
# Invoked automatically by .githooks/pre-commit (with --stage).

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

MODE="apply"
case "${1:-}" in
  --stage)   MODE="stage" ;;
  --dry-run) MODE="dry-run" ;;
  "")        MODE="apply" ;;
  *) echo "bump-version: unknown arg '${1}'" >&2; exit 2 ;;
esac

# ── Branch → bump kind ─────────────────────────────────────────────────────
BRANCH="$(git symbolic-ref --short -q HEAD || true)"   # empty when detached
case "$BRANCH" in
  fix/*)     KIND="patch" ;;
  feature/*) KIND="feature" ;;
  *)         exit 0 ;;   # main, release branches, detached HEAD → never auto-bump
esac

# ── Baseline = main's current VERSION ──────────────────────────────────────
if   git rev-parse -q --verify origin/main >/dev/null; then MAIN_REF="origin/main"
elif git rev-parse -q --verify main        >/dev/null; then MAIN_REF="main"
else exit 0   # no main ref to compare against → skip silently
fi

BASE_VERSION="$(git show "${MAIN_REF}:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
CUR_VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || true)"
[[ -z "$BASE_VERSION" || -z "$CUR_VERSION" ]] && exit 0

# ── Idempotency: only bump while still at the baseline ─────────────────────
if [[ "$CUR_VERSION" != "$BASE_VERSION" ]]; then
  exit 0   # already bumped on this branch (or ahead of main) → nothing to do
fi

# ── Compute the new version ────────────────────────────────────────────────
IFS='.' read -r MAJOR FEATURE FIXES <<< "$BASE_VERSION"
if ! [[ "$MAJOR" =~ ^[0-9]+$ && "$FEATURE" =~ ^[0-9]+$ && "$FIXES" =~ ^[0-9]+$ ]]; then
  echo "bump-version: VERSION '${BASE_VERSION}' is not MAJOR.FEATURE.FIXES — skipping." >&2
  exit 0
fi
case "$KIND" in
  patch)   NEW="${MAJOR}.${FEATURE}.$((FIXES + 1))" ;;
  feature) NEW="${MAJOR}.$((FEATURE + 1)).0" ;;
esac

PBX="Forsetti Jamf Pro.xcodeproj/project.pbxproj"
CHANGELOG="CHANGELOG.md"

if [[ "$MODE" == "dry-run" ]]; then
  echo "bump-version (dry-run): branch '${BRANCH}' → ${KIND} bump ${BASE_VERSION} → ${NEW}"
  echo "  would update: VERSION, ${PBX}, README.md, WIKI.md, ${CHANGELOG}"
  exit 0
fi

# ── Apply (targeted, narrative-preserving) ─────────────────────────────────
printf '%s\n' "$NEW" > VERSION

# pbxproj: every MARKETING_VERSION / CURRENT_PROJECT_VERSION field, regardless
# of the old value (field-anchored so nothing else is touched).
if [[ -f "$PBX" ]]; then
  perl -i -pe '
    s/(MARKETING_VERSION = )[0-9]+\.[0-9]+\.[0-9]+;/${1}'"$NEW"';/g;
    s/(CURRENT_PROJECT_VERSION = )[0-9]+\.[0-9]+\.[0-9]+;/${1}'"$NEW"';/g;
  ' "$PBX"
fi

# README: only the leading "Current release: `vX.Y.Z`" token. The release
# narrative and any "Builds on vX.Y.Z" history are left untouched.
if [[ -f README.md ]]; then
  perl -i -pe 's/(Current release: `v)[0-9]+\.[0-9]+\.[0-9]+(`)/${1}'"$NEW"'${2}/' README.md
fi

# WIKI: only the two version lines under "Current project version".
if [[ -f WIKI.md ]]; then
  perl -i -pe '
    s/(`CURRENT_PROJECT_VERSION = )[0-9]+\.[0-9]+\.[0-9]+(`)/${1}'"$NEW"'${2}/;
    s/(`MARKETING_VERSION = )[0-9]+\.[0-9]+\.[0-9]+(`)/${1}'"$NEW"'${2}/;
  ' WIKI.md
fi

# CHANGELOG: insert a dated stub section after the "## [Unreleased]" block's
# first "---" separator. Skipped if the anchor is missing or the section
# already exists (so it never duplicates).
CHANGELOG_NOTE=""
if [[ -f "$CHANGELOG" ]] && grep -q '^## \[Unreleased\]' "$CHANGELOG" && ! grep -q "^## \[${NEW}\]" "$CHANGELOG"; then
  TODAY="$(date +%F)"
  SECTION_HEADER="$([[ "$KIND" == "patch" ]] && echo "### Fixed" || echo "### Added")"
  awk -v ver="$NEW" -v day="$TODAY" -v hdr="$SECTION_HEADER" '
    BEGIN { inserted = 0; seen = 0 }
    /^## \[Unreleased\]/ { seen = 1 }
    {
      print
      if (seen == 1 && inserted == 0 && $0 == "---") {
        print ""
        print "## [" ver "] — " day
        print ""
        print hdr
        print "- _TODO: describe this change._"
        print ""
        print "### Project"
        print "- `VERSION` and pbxproj `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` set to **" ver "**."
        print ""
        print "---"
        inserted = 1
      }
    }
  ' "$CHANGELOG" > "${CHANGELOG}.bump.tmp" && mv "${CHANGELOG}.bump.tmp" "$CHANGELOG"
else
  CHANGELOG_NOTE="  (CHANGELOG stub not inserted — add a ## [${NEW}] entry by hand)"
fi

echo "bump-version: ${BASE_VERSION} → ${NEW}  (${KIND}, from ${BRANCH})${CHANGELOG_NOTE}"
echo "             remember to fill in the CHANGELOG body + README/WIKI release notes."

if [[ "$MODE" == "stage" ]]; then
  for f in VERSION "$PBX" README.md WIKI.md "$CHANGELOG"; do
    [[ -f "$f" ]] && git add -- "$f" 2>/dev/null || true
  done
fi

exit 0
