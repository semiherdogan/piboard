#!/usr/bin/env bash
# Builds, signs, packages and (optionally) notarizes PiBoard, then generates the Sparkle appcast.
#
# Every option can be given as a flag or as the environment variable in brackets:
#   --version <x.y.z>         [VERSION]       CFBundleShortVersionString (required)
#   --build-number <n>        [BUILD_NUMBER]  CFBundleVersion, monotonically increasing integer (default 1)
#   --channel <stable|beta>   [CHANNEL]       Sparkle channel for the new appcast item (default stable)
#   --notes-file <path>       [NOTES_FILE]    Markdown release notes embedded in the appcast (optional)
#   --output-dir <path>       [OUTPUT_DIR]    Artifact directory (default build/release)
#   --signing-mode <mode>     [SIGNING_MODE]  adhoc (default) or developer-id
#
# Secrets, read from the environment only:
#   SPARKLE_PRIVATE_KEY       EdDSA private key (output of `generate_keys -x`). Without it the appcast step is
#                             skipped, unless REQUIRE_APPCAST=1, which makes a missing key fatal.
#   APPLE_TEAM_ID             Required for developer-id signing.
#   APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, APPLE_API_KEY_P8
#                             App Store Connect API key used for notarization in developer-id mode.
#
# Outputs (also written to $GITHUB_OUTPUT when set): zip_path, pages_dir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="PiBoard"
PROJECT="PiBoard.xcodeproj"
SCHEME="PiBoard"
DERIVED_DATA="build/DerivedData"
SPARKLE_BIN_DIR="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
GITHUB_REPO="semiherdogan/piboard"
APPCAST_NAME="appcast.xml"
PUBLISHED_APPCAST_URL="https://semiherdogan.github.io/piboard/$APPCAST_NAME"
# Must match UpdateChannel.betaSparkleChannel in the app.
BETA_SPARKLE_CHANNEL="beta"
# Must match UpdateService.placeholderPublicEDKey and project.yml.
PLACEHOLDER_PUBLIC_ED_KEY="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
SIGNING_MODE_ADHOC="adhoc"
SIGNING_MODE_DEVELOPER_ID="developer-id"
NOTARY_ACCEPTED_STATUS="Accepted"
HTTP_OK="200"
HTTP_NOT_FOUND="404"

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CHANNEL="${CHANNEL:-stable}"
NOTES_FILE="${NOTES_FILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-build/release}"
SIGNING_MODE="${SIGNING_MODE:-$SIGNING_MODE_ADHOC}"
REQUIRE_APPCAST="${REQUIRE_APPCAST:-0}"

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
}

fail() {
    echo "error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --build-number) BUILD_NUMBER="$2"; shift 2 ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --notes-file) NOTES_FILE="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --signing-mode) SIGNING_MODE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "unknown argument: $1" ;;
    esac
done

[[ -n "$VERSION" ]] || fail "VERSION is required"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-+][0-9A-Za-z.-]+)?$ ]] || fail "VERSION '$VERSION' is not x.y or x.y.z"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "BUILD_NUMBER '$BUILD_NUMBER' must be an integer"
case "$CHANNEL" in
    stable|beta) ;;
    *) fail "CHANNEL must be stable or beta, got '$CHANNEL'" ;;
esac
case "$SIGNING_MODE" in
    "$SIGNING_MODE_ADHOC") ;;
    "$SIGNING_MODE_DEVELOPER_ID") [[ -n "${APPLE_TEAM_ID:-}" ]] || fail "APPLE_TEAM_ID is required for $SIGNING_MODE_DEVELOPER_ID signing" ;;
    *) fail "SIGNING_MODE must be $SIGNING_MODE_ADHOC or $SIGNING_MODE_DEVELOPER_ID, got '$SIGNING_MODE'" ;;
esac
if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
    fail "NOTES_FILE '$NOTES_FILE' does not exist"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
ARCHIVE_PATH="$OUTPUT_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$OUTPUT_DIR/export"
APPCAST_WORK_DIR="$OUTPUT_DIR/appcast-work"
PAGES_DIR="$OUTPUT_DIR/pages"
ZIP_NAME="$APP_NAME-$VERSION.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

# Only our own artifacts are removed so a custom OUTPUT_DIR is never wiped wholesale.
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$APPCAST_WORK_DIR" "$PAGES_DIR" "$ZIP_PATH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

step() {
    echo
    echo "==> $*"
}

step "Generating project"
scripts/fetch-node.sh
xcodegen generate

step "Running tests"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' -configuration Debug \
    -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA" test

step "Archiving $VERSION ($BUILD_NUMBER), signing mode $SIGNING_MODE"
SIGNING_SETTINGS=(CODE_SIGN_STYLE=Manual)
if [[ "$SIGNING_MODE" == "$SIGNING_MODE_DEVELOPER_ID" ]]; then
    SIGNING_SETTINGS+=("CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    SIGNING_SETTINGS+=("CODE_SIGN_IDENTITY=-" "DEVELOPMENT_TEAM=")
fi
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'generic/platform=macOS' -configuration Release \
    -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA" -archivePath "$ARCHIVE_PATH" \
    "MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" "${SIGNING_SETTINGS[@]}" archive

step "Exporting app"
mkdir -p "$EXPORT_DIR"
if [[ "$SIGNING_MODE" == "$SIGNING_MODE_DEVELOPER_ID" ]]; then
    EXPORT_OPTIONS="$TMP_DIR/ExportOptions.plist"
    plutil -create xml1 "$EXPORT_OPTIONS"
    plutil -insert method -string developer-id "$EXPORT_OPTIONS"
    plutil -insert signingStyle -string manual "$EXPORT_OPTIONS"
    plutil -insert signingCertificate -string "Developer ID Application" "$EXPORT_OPTIONS"
    plutil -insert teamID -string "$APPLE_TEAM_ID" "$EXPORT_OPTIONS"
    xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_DIR" -exportOptionsPlist "$EXPORT_OPTIONS"
else
    # Ad-hoc builds have nothing to re-sign, so the archived product is used as is.
    ditto "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"
fi

step "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

NOTARIZED="no"
if [[ "$SIGNING_MODE" == "$SIGNING_MODE_DEVELOPER_ID" ]]; then
    if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" && -n "${APPLE_API_KEY_P8:-}" ]]; then
        step "Notarizing"
        API_KEY_PATH="$TMP_DIR/AuthKey_$APPLE_API_KEY_ID.p8"
        (umask 077 && printf '%s\n' "$APPLE_API_KEY_P8" > "$API_KEY_PATH")
        NOTARY_ZIP="$TMP_DIR/notarize.zip"
        ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
        NOTARY_RESULT="$TMP_DIR/notary.json"
        xcrun notarytool submit "$NOTARY_ZIP" --key "$API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
            --issuer "$APPLE_API_ISSUER_ID" --wait --output-format json > "$NOTARY_RESULT"
        NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
        if [[ "$NOTARY_STATUS" != "$NOTARY_ACCEPTED_STATUS" ]]; then
            SUBMISSION_ID="$(plutil -extract id raw -o - "$NOTARY_RESULT")"
            xcrun notarytool log "$SUBMISSION_ID" --key "$API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
                --issuer "$APPLE_API_ISSUER_ID" || true
            fail "notarization finished with status $NOTARY_STATUS"
        fi
        xcrun stapler staple "$APP_PATH"
        xcrun stapler validate "$APP_PATH"
        NOTARIZED="yes"
    else
        echo "warning: notarization secrets missing; the Developer ID build is signed but not notarized" >&2
    fi
fi

step "Packaging $ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

APPCAST_RESULT="skipped (SPARKLE_PRIVATE_KEY not set)"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    step "Generating appcast"
    # generate_appcast silently omits signatures for an app without a real public key.
    APP_PUBLIC_ED_KEY="$(plutil -extract SUPublicEDKey raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
    if [[ -z "$APP_PUBLIC_ED_KEY" || "$APP_PUBLIC_ED_KEY" == "$PLACEHOLDER_PUBLIC_ED_KEY" ]]; then
        fail "SUPublicEDKey in project.yml is still the placeholder; see docs/RELEASING.md"
    fi
    GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
    if [[ ! -x "$GENERATE_APPCAST" ]]; then
        GENERATE_APPCAST="$(find "$DERIVED_DATA/SourcePackages/artifacts" -type f -name generate_appcast -perm -u+x | head -n 1)"
    fi
    [[ -x "$GENERATE_APPCAST" ]] || fail "generate_appcast not found under $DERIVED_DATA/SourcePackages/artifacts"

    mkdir -p "$APPCAST_WORK_DIR" "$PAGES_DIR"
    cp "$ZIP_PATH" "$APPCAST_WORK_DIR/"
    APPCAST_ARGS=(
        --ed-key-file -
        --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"
        -o "$PAGES_DIR/$APPCAST_NAME"
    )
    if [[ -n "$NOTES_FILE" && -s "$NOTES_FILE" ]]; then
        # generate_appcast pairs notes with the archive by basename.
        cp "$NOTES_FILE" "$APPCAST_WORK_DIR/$APP_NAME-$VERSION.md"
        APPCAST_ARGS+=(--embed-release-notes)
    fi
    if [[ "$CHANNEL" == "beta" ]]; then
        APPCAST_ARGS+=(--channel "$BETA_SPARKLE_CHANNEL")
    fi

    # generate_appcast keeps the items of an existing feed at the -o path, so seed it with the
    # published feed. The query string sidesteps the Pages CDN cache.
    HTTP_STATUS="$(curl -sSL -o "$PAGES_DIR/$APPCAST_NAME" -w '%{http_code}' "$PUBLISHED_APPCAST_URL?nocache=$(date +%s)")"
    case "$HTTP_STATUS" in
        "$HTTP_OK") echo "Seeded with published appcast from $PUBLISHED_APPCAST_URL" ;;
        "$HTTP_NOT_FOUND") rm -f "$PAGES_DIR/$APPCAST_NAME"; echo "No published appcast yet; starting a new feed" ;;
        *) fail "fetching $PUBLISHED_APPCAST_URL returned HTTP $HTTP_STATUS; refusing to drop feed history" ;;
    esac

    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$APPCAST_WORK_DIR"
    APPCAST_RESULT="$PAGES_DIR/$APPCAST_NAME"
elif [[ "$REQUIRE_APPCAST" == "1" ]]; then
    fail "SPARKLE_PRIVATE_KEY is required when REQUIRE_APPCAST=1"
else
    echo
    echo "SPARKLE_PRIVATE_KEY is not set; skipping appcast generation and signing."
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "zip_path=$ZIP_PATH"
        echo "pages_dir=$PAGES_DIR"
    } >> "$GITHUB_OUTPUT"
fi

step "Summary"
echo "Version:      $VERSION ($BUILD_NUMBER)"
echo "Channel:      $CHANNEL"
echo "Signing:      $SIGNING_MODE"
echo "Notarized:    $NOTARIZED"
echo "Zip:          $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1 | tr -d ' '))"
echo "Appcast:      $APPCAST_RESULT"
