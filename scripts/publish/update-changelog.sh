#!/usr/bin/env bash
# update-changelog.sh — Append changelog from git log to NPM-README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"

VERSION_TAG="${VERSION_TAG:?VERSION_TAG is required}"
NPM_VERSION="${NPM_VERSION:-$(npm_version_from_tag "$VERSION_TAG")}"

README_FILE="$PROJECT_ROOT/NPM-README.md"

# Find the previous tag (or use --all if none exists)
PREV_TAG=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 "${VERSION_TAG}^" 2>/dev/null || true)

if [ -n "$PREV_TAG" ]; then
    CHANGELOG=$(git -C "$PROJECT_ROOT" log --pretty=format:"- %s (%h)" "${PREV_TAG}..${VERSION_TAG}" --no-merges)
else
    CHANGELOG=$(git -C "$PROJECT_ROOT" log --pretty=format:"- %s (%h)" --no-merges | head -50)
fi

RELEASE_DATE=$(date -u +"%Y-%m-%d")

CHANGELOG_BLOCK=$(cat <<CHANGES

---

## Changelog v${NPM_VERSION} (${RELEASE_DATE})

${CHANGELOG}
CHANGES
)

# Check if this version already exists in README
if grep -q "v${NPM_VERSION}" "$README_FILE" 2>/dev/null; then
    info "Changelog for v${NPM_VERSION} already exists in NPM-README.md, skipping."
else
    echo "$CHANGELOG_BLOCK" >> "$README_FILE"
    success "Changelog for v${NPM_VERSION} added to NPM-README.md"
fi
