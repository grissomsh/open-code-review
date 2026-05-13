#!/usr/bin/env bash
# check-prerequisites.sh — Validate environment before publishing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"

check_required_tools() {
    local missing=0
    info "Checking required tools..."
    for cmd in go jq git tnpm shasum; do
        if command -v "$cmd" >/dev/null 2>&1; then
            info "  ${cmd}: found"
        else
            error "  ${cmd}: NOT FOUND"
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || die "Missing required tools listed above."
    success "All required tools available"
}

check_clean_git_state() {
    cd "$PROJECT_ROOT"
    local status
    status=$(git status --porcelain 2>/dev/null || true)
    if [ -n "$status" ]; then
        warn "Working tree has uncommitted changes:"
        echo "$status"
        die "Please commit or stash changes before publishing."
    fi
    success "Git working tree is clean"
}

check_git_tag() {
    cd "$PROJECT_ROOT"
    local tag="${OCR_VERSION_OVERRIDE:-}"
    if [ -z "$tag" ]; then
        tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
        if [ -z "$tag" ]; then
            die "No git tag found. Create a tag first: git tag vX.Y.Z && git push origin --tags"
        fi
        info "Using latest git tag: ${tag}"
    else
        # Validate it looks like a version
        [[ "$tag" == v* ]] || tag="v${tag}"
        if ! git rev-parse "$tag" >/dev/null 2>&1; then
            warn "Override version '${tag}' does not match any existing git tag."
            warn "Proceeding anyway (assumes dev/prerelease version)."
            return 0
        fi
        info "Using override version: ${tag}"
    fi

    # Verify tag is an ancestor of HEAD (only for real tags)
    if git rev-parse "$tag" >/dev/null 2>&1; then
        if ! git merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then
            warn "Tag '$tag' is not an ancestor of HEAD."
            die "Checkout the correct commit/branch before publishing."
        fi
    fi
    success "Git tag verified"
}

check_internal_release_repo() {
    local internal_root="${OCR_INTERNAL_RELEASE:-$HOME/internal-release}"
    if [ -d "$internal_root/.git" ]; then
        local remote_url
        remote_url=$(git -C "$internal_root" remote get-url origin 2>/dev/null || true)
        if [[ "$remote_url" != *"internal-release"* ]]; then
            die "internal-release repo at ${internal_root} doesn't look right (origin: ${remote_url})"
        fi
        success "internal-release repo found at ${internal_root}"
    else
        info "internal-release repo not found locally; will clone during publish if needed."
    fi
}

check_npm_auth() {
    local who
    who=$(tnpm whoami 2>/dev/null || true)
    if [ -z "$who" ]; then
        die "Not logged in to tnpm. Run 'tnpm login' first."
    fi
    success "tnpm authenticated as: ${who}"
}

# ── Run all checks ───────────────────────────────────────────────────────────
info "=== Pre-flight checks ==="
echo ""
check_required_tools
echo ""
check_clean_git_state
echo ""
check_git_tag
echo ""
check_internal_release_repo
echo ""
check_npm_auth
echo ""
success "All prerequisites satisfied"
