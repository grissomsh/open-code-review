#!/usr/bin/env bash
# publish-npm.sh — Run tnpm publish.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"

NPM_VERSION="${NPM_VERSION:?NPM_VERSION is required}"
VERSION_TAG="${VERSION_TAG:-v${NPM_VERSION}}"

cd "$PROJECT_ROOT"

check_already_published() {
    local published
    published=$(tnpm view "@ali/open-code-review@${NPM_VERSION}" version 2>/dev/null || true)
    if [ "$published" = "$NPM_VERSION" ]; then
        warn "Version ${NPM_VERSION} is already published to npm!"
        if confirm "Skip publish and continue?"; then
            info "Skipping publish."
            exit 0
        else
            die "Aborted by user."
        fi
    fi
}

do_publish() {
    info "Publishing @ali/open-code-review@${NPM_VERSION} ..."
    tnpm publish --no-git-tag-version
    success "Published @ali/open-code-review@${NPM_VERSION}"
}

info "=== npm publish ==="
echo ""
check_already_published
echo ""
do_publish
