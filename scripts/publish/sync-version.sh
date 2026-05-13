#!/usr/bin/env bash
# sync-version.sh — Sync package.json version with git tag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"

VERSION_TAG="${OCR_VERSION_OVERRIDE:-}"
if [ -z "$VERSION_TAG" ]; then
    VERSION_TAG=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || die "No git tag found")
fi
VERSION_TAG="$(normalize_version "$VERSION_TAG")"
NPM_VERSION="$(npm_version_from_tag "$VERSION_TAG")"

PACKAGE_JSON="$PROJECT_ROOT/package.json"
CURRENT_NPM_VERSION=$(jq -r '.version' "$PACKAGE_JSON")

info "Version resolution:"
info "  Git tag (source of truth):  ${VERSION_TAG}"
info "  npm version (to set):       ${NPM_VERSION}"
info "  package.json current:       ${CURRENT_NPM_VERSION}"

if [ "$NPM_VERSION" = "$CURRENT_NPM_VERSION" ]; then
    info "package.json version already matches. No change needed."
else
    info "Updating package.json version from ${CURRENT_NPM_VERSION} to ${NPM_VERSION}..."
    local_tmp=$(mktemp)
    jq --arg v "$NPM_VERSION" '.version = $v' "$PACKAGE_JSON" > "$local_tmp"
    mv "$local_tmp" "$PACKAGE_JSON"
    success "package.json updated"
fi

echo ""
echo "__VERSION_TAG__=${VERSION_TAG}"
echo "__NPM_VERSION__=${NPM_VERSION}"
