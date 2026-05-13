#!/usr/bin/env bash
# copy-to-internal-repo.sh — Upload artifacts to internal-release repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="$(resolve_project_root)"

VERSION_TAG="${VERSION_TAG:?VERSION_TAG is required}"
NPM_VERSION="${NPM_VERSION:-$(npm_version_from_tag "$VERSION_TAG")}"

INTERNAL_ROOT="${OCR_INTERNAL_RELEASE:-$HOME/internal-release}"
BIN_DIR="${INTERNAL_ROOT}/bin"
VERSION_BIN_DIR="${BIN_DIR}/${VERSION_TAG}"

DIST_DIR="${PROJECT_ROOT}/dist"

# ── Ensure internal-release repo exists and is up to date ───────────────────
ensure_internal_repo() {
    if [ -d "$INTERNAL_ROOT/.git" ]; then
        info "Pulling latest from internal-release repo..."
        (cd "$INTERNAL_ROOT" && git pull --rebase origin master 2>/dev/null || git pull --rebase)
    else
        info "Cloning internal-release repo to ${INTERNAL_ROOT}..."
        mkdir -p "$(dirname "$INTERNAL_ROOT")"
        git clone git@gitlab.alibaba-inc.com:open-code-review/internal-release.git "$INTERNAL_ROOT"
    fi
    success "internal-release repo ready"
}

# ── Copy binaries and generate checksums ─────────────────────────────────────
copy_artifacts() {
    mkdir -p "$VERSION_BIN_DIR"
    rm -f "$VERSION_BIN_DIR"/opencodereview-*

    local count=0
    for f in "$DIST_DIR"/opencodereview-${VERSION_TAG}-*; do
        [ -f "$f" ] || continue
        local src_base
        src_base=$(basename "$f")
        # Strip version prefix: opencodereview-v1.0-darwin-arm64 → opencodereview-darwin-arm64
        local target_name="${src_base/opencodereview-${VERSION_TAG}-/opencodereview-}"
        info "  Copying ${target_name}"
        cp "$f" "$VERSION_BIN_DIR/${target_name}"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        die "No binaries found in ${DIST_DIR} matching pattern opencodereview-${VERSION_TAG}-*"
    fi

    success "Copied ${count} binaries"
}

generate_checksums() {
    (cd "$VERSION_BIN_DIR" && shasum -a 256 opencodereview-* | sort > sha256sum.txt)
    success "sha256sum.txt generated"
}

update_version_file() {
    local last_line
    last_line=$(tail -1 "$INTERNAL_ROOT/VERSION" 2>/dev/null || true)
    if [ "$last_line" != "$VERSION_TAG" ]; then
        printf "%s\n" "$VERSION_TAG" >> "$INTERNAL_ROOT/VERSION"
        info "VERSION file updated (added ${VERSION_TAG})"
    else
        info "VERSION file already ends with ${VERSION_TAG}, skipping append"
    fi
}

commit_and_push() {
    cd "$INTERNAL_ROOT"

    git add -A

    if git diff --cached --quiet; then
        info "No changes to commit — binaries already match."
        return 0
    fi

    info "Committing to internal-release repo..."
    git commit -m "release: opencodereview ${VERSION_TAG} (npm ${NPM_VERSION})"
    git push origin master 2>/dev/null || git push
    success "Pushed to internal-release repo"
}

# ── Execution ────────────────────────────────────────────────────────────────
info "=== Publishing artifacts to internal-release repo ==="
info "Version: ${VERSION_TAG}"
info "Target: ${INTERNAL_ROOT}"
echo ""

ensure_internal_repo
copy_artifacts
generate_checksums
update_version_file
commit_and_push

echo ""
success "Artifacts published successfully"
