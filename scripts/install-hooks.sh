#!/usr/bin/env bash
set -euo pipefail

# install-hooks.sh — Point git at the tracked .githooks/ directory.
#
# Run once per clone:
#
#     bash scripts/install-hooks.sh
#
# What it does:
#   1. Sets `git config core.hooksPath .githooks` for this clone. Every
#      hook under `.githooks/` becomes active immediately; no copying
#      into `.git/hooks/` needed.
#   2. Makes the hook files executable (required for git to run them).
#   3. Warns if the dev is missing optional tools (swiftlint, gitleaks)
#      whose absence changes which local checks can run.
#
# Rationale for tracked hooks (vs. the default untracked .git/hooks/):
#   • The post-commit hook drives auto-versioning and CHANGELOG
#     promotion. Without it installed, a dev's commits don't bump the
#     version and the CHANGELOG drifts.
#   • The pre-push hook blocks external authorship footers and runs build + test
#     before a branch leaves the workstation.
#   • Local hooks complement hosted pull-request checks; they do not replace
#     review or check monitoring after a branch is pushed.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "install-hooks.sh: not inside a git repository. Run from within the Forsetti checkout." >&2
  exit 1
fi
cd "$REPO_ROOT"

if [[ ! -d ".githooks" ]]; then
  echo "install-hooks.sh: .githooks/ directory not found at repo root." >&2
  echo "Expected: $REPO_ROOT/.githooks/" >&2
  exit 1
fi

# ── Set the hooks path ────────────────────────────────────────────────────
git config core.hooksPath .githooks
echo "✓ core.hooksPath = .githooks"

# ── Make every hook executable (and nothing else) ────────────────────────
HOOK_NAMES=(pre-commit post-commit pre-push)
for hook in "${HOOK_NAMES[@]}"; do
  path=".githooks/$hook"
  if [[ -f "$path" ]]; then
    chmod +x "$path"
    echo "✓ $path executable"
  fi
done

# ── Optional-tool availability check ─────────────────────────────────────
# Missing tools aren't fatal — the hooks degrade gracefully — but surface
# the gap once at install time so devs know what's not running.
echo ""
echo "Optional tools used by the pre-commit hook:"

if command -v swiftlint >/dev/null 2>&1; then
  echo "  ✓ swiftlint ($(swiftlint version 2>/dev/null || echo 'version unknown'))"
else
  echo "  ✗ swiftlint not installed — lint check will be skipped."
  echo "    Install: brew install swiftlint"
fi

if command -v gitleaks >/dev/null 2>&1; then
  echo "  ✓ gitleaks ($(gitleaks version 2>/dev/null || echo 'version unknown'))"
else
  echo "  ✗ gitleaks not installed — will fall back to a conservative inline"
  echo "    scanner (AWS keys, PEM private-key headers, bearer-like tokens)."
  echo "    Install: brew install gitleaks"
fi

echo ""
echo "Hook behavior:"
echo "  pre-commit  → artifact policy, SwiftLint (staged files), secret scan"
echo "  post-commit → auto version bump + CHANGELOG promotion"
echo "  pre-push    → authorship-footer block and macOS build/test"
echo ""
echo "To bypass a single invocation: git commit/push --no-verify"
echo "To skip just the pre-push build/test: SKIP_TESTS=1 or SKIP_BUILD=1"
echo ""
echo "install-hooks.sh: done."
