#!/usr/bin/env bash
#
# publish-all.sh — Build → Upload → Sync version → Update changelog → Publish npm package
#
# Usage:
#   ./scripts/publish/publish-all.sh              # Release latest git tag
#   ./scripts/publish/publish-all.sh v1.2.3       # Release specific tag
#
# Environment variables:
#   OCR_FORCE_YES          Set to 1 to skip confirmation prompts (CI mode)
#   OCR_INTERNAL_RELEASE   Override path to internal-release repo
#   OCR_VERSION_OVERRIDE   Use this version instead of latest git tag
#   OCR_SKIP_BUILD         Skip build step (use existing dist/)
#   OCR_SKIP_INTERNAL      Skip uploading to internal-release repo
#   OCR_SKIP_NPM           Skip npm publish
#
# Exit codes:
#   0   Success
#   1   General failure
#   2   Prerequisite check failed
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"
cd "$PROJECT_ROOT"

# ── Configuration ─────────────────────────────────────────────────────────────
SKIP_BUILD="${OCR_SKIP_BUILD:-0}"
SKIP_INTERNAL="${OCR_SKIP_INTERNAL:-0}"
SKIP_NPM="${OCR_SKIP_NPM:-0}"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  OpenCodeReview — Automated Publisher     ${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""

# ── Resolve version from git tag ─────────────────────────────────────────────
VERSION_TAG="${OCR_VERSION_OVERRIDE:-}"
if [ -z "$VERSION_TAG" ]; then
    VERSION_TAG=$(git describe --tags --abbrev=0 2>/dev/null || die "No git tag found. Create one: git tag vX.Y.Z && git push origin --tags")
fi
VERSION_TAG="$(normalize_version "$VERSION_TAG")"
NPM_VERSION="$(npm_version_from_tag "$VERSION_TAG")"
export VERSION_TAG NPM_VERSION

info "Release plan:"
info "  Git tag:     ${VERSION_TAG}"
info "  npm version: ${NPM_VERSION}"
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────
run_step "Prerequisites" "bash \"$SCRIPT_DIR/check-prerequisites.sh\""

# ── Confirm ───────────────────────────────────────────────────────────────────
if ! confirm "Ready to publish ${VERSION_TAG}. Continue?"; then
    info "Aborted by user."
    exit 0
fi

# ── Trap for partial failures ─────────────────────────────────────────────────
PUBLISH_STARTED=0
trap 'on_failure' ERR INT TERM

on_failure() {
    error ""
    error "Publish FAILED at step where PUBLISH_STARTED=${PUBLISH_STARTED}"
    error ""

    if [ "$PUBLISH_STARTED" -ge 1 ] && [ "$PUBLISH_STARTED" -lt 4 ]; then
        warn "ARTIFACTS MAY BE PARTIALLY PUBLISHED."
        warn "Check the following:"
        [ "$PUBLISH_STARTED" -ge 2 ] && warn "  - internal-release repo: may need rollback"
        [ "$PUBLISH_STARTED" -ge 3 ] && warn "  - NPM-README.md: may have changelog without npm publish"
        [ "$PUBLISH_STARTED" -ge 4 ] && warn "  - npm registry: may have been published"
    fi

    if [ "$PUBLISH_STARTED" -lt 3 ]; then
        warn "package.json version may need to be reverted to its original value."
    fi

    error "Full output log above. Fix the issue and re-run."
    exit 1
}

# ── Step 1: Build all platforms (reuse Makefile) ─────────────────────────────
if [ "$SKIP_BUILD" = "1" ]; then
    warn "Skipping build (--skip-build)"
    PUBLISH_STARTED=1
else
    run_step "Building binaries (make dist)" \
        "make -C \"$PROJECT_ROOT\" dist"
    PUBLISH_STARTED=1
fi

# ── Step 2: Sync package.json version ────────────────────────────────────────
run_step "Syncing package.json version" \
    "bash \"$SCRIPT_DIR/sync-version.sh\""
PUBLISH_STARTED=2

# ── Step 3: Copy to internal-release repo ────────────────────────────────────
if [ "$SKIP_INTERNAL" = "1" ]; then
    warn "Skipping internal repo upload (--skip-internal)"
    PUBLISH_STARTED=3
else
    run_step "Uploading to internal-release repo" \
        "bash \"$SCRIPT_DIR/copy-to-internal-repo.sh\""
    PUBLISH_STARTED=3
fi

# ── Step 4: Update changelog ─────────────────────────────────────────────────
run_step "Updating NPM-README.md changelog" \
    "bash \"$SCRIPT_DIR/update-changelog.sh\""
PUBLISH_STARTED=4

# ── Step 5: npm publish ──────────────────────────────────────────────────────
if [ "$SKIP_NPM" = "1" ]; then
    warn "Skipping npm publish (--skip-npm)"
else
    run_step "Publishing to npm (tnpm publish)" \
        "bash \"$SCRIPT_DIR/publish-npm.sh\""
fi
PUBLISH_STARTED=5

# ── Commit version changes in main repo ──────────────────────────────────────
info "Committing version changes in main repo..."
git add package.json NPM-README.md
if ! git diff --cached --quiet; then
    git commit -m "chore(release): bump version to ${VERSION_TAG}"
    success "Committed version bump to main repo"
else
    info "No new changes to commit in main repo."
fi

# ── Success ───────────────────────────────────────────────────────────────────
trap - ERR INT TERM

echo ""
echo -e "${GREEN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}  RELEASE COMPLETE                         ${RESET}"
echo -e "${GREEN}${BOLD}============================================${RESET}"
echo ""
echo -e "  ${BOLD}@ali/open-code-review@${NPM_VERSION}${RESET}"
echo -e "  Binary version: ${VERSION_TAG}"
echo -e "  Platforms: linux/amd64, linux/arm64, darwin/amd64, darwin/arm64"
echo ""
