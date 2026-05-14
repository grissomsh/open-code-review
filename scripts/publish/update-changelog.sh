#!/usr/bin/env bash
# update-changelog.sh — Prepend changelog from git log to CHANGELOG.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"

VERSION_TAG="${VERSION_TAG:?VERSION_TAG is required}"
NPM_VERSION="${NPM_VERSION:-$(npm_version_from_tag "$VERSION_TAG")}"

CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"

# Create if not exists
if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "# Changelog" > "$CHANGELOG_FILE"
fi

# Find the previous tag (or use --all if none exists)
PREV_TAG=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 "${VERSION_TAG}^" 2>/dev/null || true)

if [ -n "$PREV_TAG" ]; then
    CHANGELOG=$(git -C "$PROJECT_ROOT" log --pretty=format:"- %s (%h)" "${PREV_TAG}..${VERSION_TAG}" --no-merges)
else
    CHANGELOG=$(git -C "$PROJECT_ROOT" log --pretty=format:"- %s (%h)" --no-merges | head -50)
fi

RELEASE_DATE=$(date -u +"%Y-%m-%d")

# Check if this version already exists
if grep -q "v${NPM_VERSION}" "$CHANGELOG_FILE" 2>/dev/null; then
    info "Changelog for v${NPM_VERSION} already exists, skipping."
else
    # Build new content: heading + new block + rest of file
    TEMP_FILE=$(mktemp)
    echo "# Changelog" > "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "## v${NPM_VERSION} (${RELEASE_DATE})" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "$CHANGELOG" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    # Append existing entries (skip the original heading line)
    tail -n +2 "$CHANGELOG_FILE" >> "$TEMP_FILE"
    mv "$TEMP_FILE" "$CHANGELOG_FILE"
    success "Changelog for v${NPM_VERSION} added to CHANGELOG.md"
fi
