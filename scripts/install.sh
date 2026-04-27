#!/usr/bin/env sh
# install.sh — Install or upgrade OpenCodeReview CLI
#
# Usage (pipelined):
#   curl -fsSL https://git.cn-hangzhou.oss-cdn.aliyun-inc.com/opencodereview-cli/install.sh | sh
#   OCR_VERSION=v0.1.0 curl -fsSL ... | sh
#
# Usage (standalone):
#   sh install.sh
#   OCR_VERSION=v0.1.0 sh install.sh
#
# Environment variables:
#   OCR_VERSION   Pin a specific version (e.g., v0.1.0). Defaults to "latest".
#   INSTALL_DIR     Override install destination (default: /usr/local/bin).

set -eu

# ── Configuration ────────────────────────────────────────────────────────────
BASE_URL="https://code.alibaba-inc.com/lizhengfeng.lzf/opencodereview-cli/raw/master/dist"
BINARY_NAME="opencodereview"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# ── Logging ──────────────────────────────────────────────────────────────────
info()  { printf "[INFO]  %s\n" "$*" >&2; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

# ── Cleanup trap ─────────────────────────────────────────────────────────────
TMPDIR_WORK=""
cleanup() {
    if [ -n "$TMPDIR_WORK" ] && [ -d "$TMPDIR_WORK" ]; then
        rm -rf "$TMPDIR_WORK"
    fi
}
trap cleanup EXIT INT TERM

# ── Detect OS & Arch ─────────────────────────────────────────────────────────
detect_platform() {
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64|amd64|x64) ARCH="amd64" ;;
        aarch64|arm64)    ARCH="arm64" ;;
        *) die "Unsupported architecture: $ARCH (need amd64 or arm64)" ;;
    esac

    case "$OS" in
        linux|darwin) ;;
        *) die "Unsupported operating system: $OS (need linux or darwin)" ;;
    esac

    info "Detected platform: ${OS}/${ARCH}"
}

# ── Resolve version ──────────────────────────────────────────────────────────
resolve_version() {
    if [ -n "${OCR_VERSION:-}" ]; then
        VERSION="$OCR_VERSION"
        VERSION="v$(echo "$VERSION" | sed 's/^v//')"
        info "Using pinned version: ${VERSION}"
        return
    fi

    # Try fetching latest version from remote
    info "Fetching latest version..."
    VERSION=$(curl -fsSL --retry 3 --retry-delay 2 "${BASE_URL}/VERSION" 2>/dev/null || true)
    if [ -n "$VERSION" ]; then
        info "Latest version: ${VERSION}"
        return
    fi

    # Fallback: detect locally built binary in dist/
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
    if [ -n "$PROJECT_ROOT" ] && [ -d "${PROJECT_ROOT}/dist" ]; then
        LOCAL_BIN=""
        # Prefer platform-specific binary, fall back to generic one
        for pattern in \
            "${BINARY_NAME}-${VERSION:-*}-${OS}-${ARCH}" \
            "${BINARY_NAME}-${VERSION:-*}-${OS}-*" \
            "${BINARY_NAME}"; do
            LOCAL_BIN=$(ls "${PROJECT_ROOT}/dist/${pattern}" 2>/dev/null | head -1 || true)
            if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN" ]; then
                break
            fi
        done
        if [ -n "$LOCAL_BIN" ] && [ -f "$LOCAL_BIN" ]; then
            VERSION=$("$LOCAL_BIN" version 2>/dev/null | awk '{print $NF}' || echo "local")
            VERSION="v$(echo "$VERSION" | sed 's/^v//')"
            LOCAL_BINARY="$LOCAL_BIN"
            warn "Remote unavailable, using local build: ${VERSION}"
            warn "  Source: ${LOCAL_BINARY}"
            return
        fi
    fi

    die "Cannot determine version. Set OCR_VERSION explicitly, or build locally with 'make build'."
}

# ── Download / locate binary ─────────────────────────────────────────────────
locate_or_download_binary() {
    # If a local binary was already resolved during version detection, use it directly
    if [ -n "${LOCAL_BINARY:-}" ]; then
        DEST="$LOCAL_BINARY"
        info "Using local binary: ${DEST}"
        return
    fi

    BINARY_FILE="${BINARY_NAME}-${VERSION}-${OS}-${ARCH}"
    DOWNLOAD_URL="${BASE_URL}/${BINARY_FILE}"

    TMPDIR_WORK=$(mktemp -d)
    DEST="${TMPDIR_WORK}/${BINARY_NAME}"

    info "Downloading ${DOWNLOAD_URL} ..."
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$DEST" "$DOWNLOAD_URL"; then
        die "Download failed. Check that version '${VERSION}' exists for ${OS}/${ARCH}."
    fi

    chmod +x "$DEST"

    # Verify checksum if available
    CHECKSUM_URL="${BASE_URL}/sha256sum-${VERSION}.txt"
    EXPECTED_CHECKSUM=$(curl -fsSL --retry 2 "$CHECKSUM_URL" 2>/dev/null | grep "$BINARY_FILE" | awk '{print $1}' || true)
    if [ -n "$EXPECTED_CHECKSUM" ]; then
        ACTUAL_CHECKSUM=$(shasum -a 256 "$DEST" | awk '{print $1}')
        if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
            die "Checksum mismatch! Expected: ${EXPECTED_CHECKSUM}, Got: ${ACTUAL_CHECKSUM}"
        fi
        info "Checksum verified."
    else
        warn "Checksum file not found at ${CHECKSUM_URL}; skipping integrity check."
    fi
}

# ── Install ──────────────────────────────────────────────────────────────────
install_binary() {
    TARGET="${INSTALL_DIR}/${BINARY_NAME}"

    # Ensure install directory exists
    if [ ! -d "$INSTALL_DIR" ]; then
        if command -v sudo >/dev/null 2>&1; then
            info "Creating install directory: ${INSTALL_DIR}"
            sudo mkdir -p "$INSTALL_DIR"
        else
            die "Install directory does not exist and sudo is unavailable: ${INSTALL_DIR}"
        fi
    fi

    if [ -f "$TARGET" ]; then
        CURRENT_VER=$("$TARGET" version 2>/dev/null | head -1 || echo "unknown")
        warn "Existing installation found (${CURRENT_VER}), replacing with ${VERSION}."
    fi

    if [ ! -w "$INSTALL_DIR" ] && ! [ "$(id -u)" = "0" ]; then
        info "Installing to ${INSTALL_DIR} (sudo required)..."
        sudo cp "$DEST" "$TARGET"
    else
        cp "$DEST" "$TARGET"
    fi

    info "Installed: ${TARGET}"
}

# ── Verify installation ──────────────────────────────────────────────────────
verify_install() {
    if command -v "${INSTALL_DIR}/${BINARY_NAME}" >/dev/null 2>&1; then
        INSTALLED_VER=$("${INSTALL_DIR}/${BINARY_NAME}" version 2>/dev/null || echo "?")
        info ""
        info "OpenCodeReview ${INSTALLED_VER} is ready!"
        info ""
        info "Quick start:"
        info "  ocr version             Show version info"
        info "  ocr config set          Configure your LLM provider"
        info "  ocr review              Start a code review"
    else
        warn ""
        warn "Installation completed but '${BINARY_NAME}' is not on PATH."
        warn "Add ${INSTALL_DIR} to your PATH, or run directly:"
        warn "  ${TARGET} version"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    info "OpenCodeReview CLI Installer"
    info "==================="

    detect_platform
    resolve_version
    locate_or_download_binary
    install_binary
    verify_install
}

main
