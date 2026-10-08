#!/usr/bin/env bash
set -euo pipefail

NODE_VERSION="24.21.0"
SHA256_ARM64="bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057"
SHA256_X64="1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$REPO_ROOT/Runtime/node"

# Only bin/node and npm are used; headers are for node-gyp, which Pi does not need.
trim_runtime() {
    local TRIM_PATHS=(
        include
        share
        CHANGELOG.md
        README.md
        lib/node_modules/corepack
        bin/corepack
    )
    local TRIM_PATH
    for TRIM_PATH in "${TRIM_PATHS[@]}"; do
        rm -rf "${DEST_DIR:?}/$TRIM_PATH"
    done
}

if [[ -x "$DEST_DIR/bin/node" ]]; then
    CURRENT_VERSION="$("$DEST_DIR/bin/node" --version)"
    if [[ "$CURRENT_VERSION" == "v$NODE_VERSION" ]]; then
        echo "Runtime/node already present at $CURRENT_VERSION, skipping download."
        trim_runtime
        "$DEST_DIR/bin/node" --version
        exit 0
    fi
fi

ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        PLATFORM="darwin-arm64"
        EXPECTED_SHA256="$SHA256_ARM64"
        ;;
    x86_64)
        PLATFORM="darwin-x64"
        EXPECTED_SHA256="$SHA256_X64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

TARBALL_NAME="node-v$NODE_VERSION-$PLATFORM.tar.gz"
TARBALL_URL="https://nodejs.org/dist/v$NODE_VERSION/$TARBALL_NAME"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading $TARBALL_URL"
curl -fsSL -o "$TMP_DIR/$TARBALL_NAME" "$TARBALL_URL"

ACTUAL_SHA256="$(shasum -a 256 "$TMP_DIR/$TARBALL_NAME" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "sha256 mismatch for $TARBALL_NAME: expected $EXPECTED_SHA256, got $ACTUAL_SHA256" >&2
    exit 1
fi

tar -xzf "$TMP_DIR/$TARBALL_NAME" -C "$TMP_DIR"

mkdir -p "$REPO_ROOT/Runtime"
rm -rf "$DEST_DIR"
mv "$TMP_DIR/node-v$NODE_VERSION-$PLATFORM" "$DEST_DIR"
trim_runtime

"$DEST_DIR/bin/node" --version
