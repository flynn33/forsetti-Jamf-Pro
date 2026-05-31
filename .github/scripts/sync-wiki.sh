#!/usr/bin/env bash
set -euo pipefail

WIKI_DIR="${1:?Usage: sync-wiki.sh <wiki-dir> <repo-dir>}"
REPO_DIR="${2:?Usage: sync-wiki.sh <wiki-dir> <repo-dir>}"
VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"

mkdir -p "$WIKI_DIR"

cat > "$WIKI_DIR/Home.md" <<EOF
# Forsetti

Version: \`v${VERSION}\`

Forsetti is a SwiftUI Jamf Pro administration app with retail-safe branding,
Forsetti runtime manifests, secure credential storage, diagnostics, reporting,
inventory search, support technician workflows, prestage workflows, and
deployment tracking.
EOF

cat > "$WIKI_DIR/_Sidebar.md" <<'EOF'
## Navigation

- [[Home]]
EOF

echo "wiki_synced=true"
