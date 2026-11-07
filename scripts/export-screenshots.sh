#!/usr/bin/env bash
# Copies the README screenshots that MonkeyTests.testReadmeScreenshots attached to a result bundle
# into docs/images as <name>.png, scaled down so the repository stays small.
set -euo pipefail

usage() {
    echo "usage: $0 <result.xcresult> <output-dir>" >&2
    exit 64
}

[[ $# -eq 2 ]] || usage
RESULT="$1"
OUTPUT_DIR="$2"
# Must match screenshotAttachmentPrefix in PiBoardUITests/MonkeyTests.swift.
PREFIX="readme-"
# Longest side in pixels; the window is captured at Retina scale.
MAX_SIDE=2000

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK_DIR" >/dev/null

count=0
while IFS=$'\t' read -r exported suggested; do
    name="${suggested#"$PREFIX"}"
    # xcresulttool appends _<index>_<uuid>.<ext>; strip only that, so names may contain underscores.
    name="$(sed -E 's/_[0-9]+_[0-9A-Fa-f-]{36}\.[A-Za-z]+$//' <<<"$name")"
    sips -Z "$MAX_SIDE" "$WORK_DIR/$exported" --out "$OUTPUT_DIR/$name.png" >/dev/null
    echo "wrote $OUTPUT_DIR/$name.png"
    count=$((count + 1))
done < <(jq -r --arg prefix "$PREFIX" \
    '.[] | .attachments[]? | select(.suggestedHumanReadableName | startswith($prefix)) | [.exportedFileName, .suggestedHumanReadableName] | @tsv' \
    "$WORK_DIR/manifest.json")

if [[ $count -eq 0 ]]; then
    echo "no screenshots found in $RESULT" >&2
    exit 1
fi
