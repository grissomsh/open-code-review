#!/usr/bin/env bash
#
# release.sh — Build all platform binaries and push to Alibaba Cloud OSS
#
# Usage:
#   ./scripts/release.sh              # Builds using latest git tag as version
#   ./scripts/release.sh v0.1.0       # Explicit version tag
#
# Prerequisites:
#   - ossutil configured (run: ossutil config)
#   - Git tag exists for the version (or pass version explicitly)
#   - Go 1.25+ installed
#
# Environment variables:
#   OSS_ENDPOINT      OSS endpoint URL (default: oss-cn-hangzhou.aliyuncs.com)
#   OSS_BUCKET        Bucket name override
#   OSS_PREFIX        Path prefix within bucket (default: opencodereview-cli)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENDPOINT="${OSS_ENDPOINT:-oss-cn-hangzhou.aliyuncs.com}"
BUCKET="${OSS_BUCKET:-git.cn-hangzhou}"
PREFIX="${OSS_PREFIX:-opencodereview-cli}"
OSS_PATH="oss://${BUCKET}/${PREFIX}"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*"; }
die()   { error "$*"; exit 1; }

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    VERSION=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || true)
    if [ -z "$VERSION" ]; then
        die "No git tag found. Pass a version explicitly or create a tag first."
    fi
    info "Using latest git tag: ${VERSION}"
else
    [[ "$VERSION" != v* ]] && VERSION="v${VERSION}"
fi

info "=== OpenCodeReview Release: ${VERSION} ==="

# ── Pre-flight checks ────────────────────────────────────────────────────────
check_prereq() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}
check_prereq go
check_prereq ossutil

cd "$PROJECT_ROOT"
if [ -n "$(git status --porcelain)" ]; then
    warn "Working tree has uncommitted changes. Proceeding anyway..."
fi

# ── Build all platforms ──────────────────────────────────────────────────────
DIST_DIR="${PROJECT_ROOT}/dist"
mkdir -p "$DIST_DIR"
rm -f "${DIST_DIR}/opencodereview-${VERSION}-"*

GIT_COMMIT="$(git rev-parse --short HEAD)"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LD_FLAGS="-s -w -X main.Version=${VERSION} -X main.GitCommit=${GIT_COMMIT} -X main.BuildDate=${BUILD_DATE}"

TARGETS=(
    "linux/amd64"
    "linux/arm64"
    "darwin/amd64"
    "darwin/arm64"
)

for pair in "${TARGETS[@]}"; do
    GOOS="${pair%/*}"
    GOARCH="${pair#*/}"
    OS_ARCH="${GOOS}-${GOARCH}"
    OUTPUT_NAME="opencodereview-${VERSION}-${OS_ARCH}"

    info "Building ${GOOS}/${GOARCH} → ${OUTPUT_NAME}"
    CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
        go build -ldflags "${LD_FLAGS}" \
        -o "${DIST_DIR}/${OUTPUT_NAME}" \
        ./cmd/opencodereview
done

# ── Generate per-version checksum file ───────────────────────────────────────
CHECKSUM_FILE="${DIST_DIR}/sha256sum-${VERSION}.txt"

info "Generating checksums: sha256sum-${VERSION}.txt"
(cd "$DIST_DIR" && shasum -a 256 opencodereview-"${VERSION}"-* | sort > "sha256sum-${VERSION}.txt")

info "Checksum contents:"
cat "$CHECKSUM_FILE" | while read -r line; do echo "    $line"; done

# ── Upload to OSS ────────────────────────────────────────────────────────────
info ""
info "Uploading to ${OSS_PATH} ..."

for f in "${DIST_DIR}"/opencodereview-"${VERSION}"-*; do
    BASENAME="$(basename "$f")"
    [[ "$BASENAME" == sha256sum-* ]] && continue
    info "  Uploading ${BASENAME} ..."
    ossutil cp "$f" "${OSS_PATH}/${BASENAME}" \
        --endpoint "$ENDPOINT" \
        --acl public-read \
        --meta "Cache-Control:max-age=31536000"
done

info "  Uploading sha256sum-${VERSION}.txt ..."
ossutil cp "$CHECKSUM_FILE" "${OSS_PATH}/sha256sum-${VERSION}.txt" \
    --endpoint "$ENDPOINT" \
    --acl public-read

info "  Uploading install.sh ..."
ossutil cp "${SCRIPT_DIR}/install.sh" "${OSS_PATH}/install.sh" \
    --endpoint "$ENDPOINT" \
    --acl public-read \
    --meta "Content-Type:text/x-sh"

echo -n "$VERSION" > "${DIST_DIR}/VERSION"
info "  Uploading VERSION sentinel ..."
ossutil cp "${DIST_DIR}/VERSION" "${OSS_PATH}/VERSION" \
    --endpoint "$ENDPOINT" \
    --acl public-read \
    --meta "Cache-Control:no-cache"

# ── Summary ──────────────────────────────────────────────────────────────────
CDN_URL="https://${BUCKET}.oss-cdn.aliyuncs.com/${PREFIX}"

info ""
info "=== Release ${VERSION} published ==="
info ""
info "Install (latest):"
info "  curl -fsSL ${CDN_URL}/install.sh | sh"
info ""
info "Pinned install:"
info "  OCR_VERSION=${VERSION} curl -fsSL ${CDN_URL}/install.sh | sh"
info ""
info "Direct downloads:"
for pair in "${TARGETS[@]}"; do
    GOOS="${pair%/*}"
    GOARCH="${pair#*/}"
    info "  ${CDN_URL}/opencodereview-${VERSION}-${GOOS}-${GOARCH}"
done
