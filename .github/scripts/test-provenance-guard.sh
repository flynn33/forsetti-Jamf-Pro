#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/.github/scripts/check-provenance-markers.sh"

if [[ ! -x "$CHECKER" ]]; then
  echo "missing executable checker: $CHECKER" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

new_repo() {
  local repo="$TMP_ROOT/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Forsetti Test"
  git -C "$repo" config user.email "forsetti@example.invalid"
  printf '%s\n' "Forsetti clean fixture" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "Initial fixture"
  printf '%s\n' "$repo"
}

expect_pass() {
  local name="$1"
  local repo="$2"
  if "$CHECKER" "$repo" > "$TMP_ROOT/$name.out" 2>&1; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    cat "$TMP_ROOT/$name.out"
    exit 1
  fi
}

expect_fail() {
  local name="$1"
  local repo="$2"
  if "$CHECKER" "$repo" > "$TMP_ROOT/$name.out" 2>&1; then
    echo "FAIL $name: checker unexpectedly passed"
    exit 1
  fi
  if ! grep -q "forbidden provenance marker" "$TMP_ROOT/$name.out"; then
    echo "FAIL $name: expected provenance finding"
    cat "$TMP_ROOT/$name.out"
    exit 1
  fi
  echo "PASS $name"
}

clean_repo="$(new_repo clean)"
expect_pass "clean_repository" "$clean_repo"

content_repo="$(new_repo content)"
printf '%s\n' "Built with Open""A""I tooling" > "$content_repo/notes.txt"
git -C "$content_repo" add notes.txt
git -C "$content_repo" commit -q -m "Add notes"
expect_fail "content_marker" "$content_repo"

path_repo="$(new_repo path)"
path_marker="Chat""GPT"
printf '%s\n' "clean content" > "$path_repo/$path_marker-notes.txt"
git -C "$path_repo" add "$path_marker-notes.txt"
git -C "$path_repo" commit -q -m "Add notes"
expect_fail "path_marker" "$path_repo"

message_repo="$(new_repo message)"
printf '%s\n' "clean content" > "$message_repo/message.txt"
git -C "$message_repo" add message.txt
git -C "$message_repo" commit -q -m "Prepared with Clau""de"
expect_fail "message_marker" "$message_repo"

event_repo="$(new_repo event)"
event_file="$TMP_ROOT/event.json"
printf '{"pull_request":{"title":"Clean title","body":"Made with %s"}}\n' "Gem""ini" > "$event_file"
GITHUB_EVENT_PATH="$event_file" expect_fail "event_marker" "$event_repo"

word_repo="$(new_repo word)"
printf '%s\n' "Contains A""I provenance wording" > "$word_repo/word.txt"
git -C "$word_repo" add word.txt
git -C "$word_repo" commit -q -m "Add wording"
expect_fail "standalone_marker" "$word_repo"
