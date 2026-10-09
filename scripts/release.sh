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
# Emergency switches, read from the environment only:
#   SKIP_LAUNCH_CHECK=1       Skip the launch smoke test that runs the built app for a few seconds.
#
# Secrets, read from the environment only:
#   SPARKLE_PRIVATE_KEY       EdDSA private key (output of `generate_keys -x`). Without it the appcast step is
#                             skipped, unless REQUIRE_APPCAST=1, which makes a missing key fatal.
#   APPLE_TEAM_ID             Required for developer-id signing.
#   APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, APPLE_API_KEY_P8
#                             App Store Connect API key used for notarization in developer-id mode.
#
# Outputs (also written to $GITHUB_OUTPUT when set): zip_path, pages_dir, release_assets (zip and deltas, one per line).
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
GITHUB_RELEASE_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download"
# Previous archives to fetch for delta generation; two covers users one or two releases behind.
DELTA_PREVIOUS_VERSIONS=2
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
SKIP_LAUNCH_CHECK="${SKIP_LAUNCH_CHECK:-0}"
LAUNCH_CHECK_SECONDS=3

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

# Unit tests only: the XCUITest monkey test needs a real session and display, which the CI runner does not have.
step "Running tests"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' -configuration Debug \
    -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA" -only-testing:PiBoardTests test

step "Archiving $VERSION ($BUILD_NUMBER), signing mode $SIGNING_MODE"
SIGNING_SETTINGS=(CODE_SIGN_STYLE=Manual)
if [[ "$SIGNING_MODE" == "$SIGNING_MODE_DEVELOPER_ID" ]]; then
    SIGNING_SETTINGS+=("CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    # Hardened runtime enforces library validation, which rejects ad-hoc signed frameworks (no Team ID),
    # so dyld aborts on Sparkle. It is only needed for notarization, which ad-hoc builds cannot get.
    SIGNING_SETTINGS+=("CODE_SIGN_IDENTITY=-" "DEVELOPMENT_TEAM=" ENABLE_HARDENED_RUNTIME=NO)
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
if [[ "$SIGNING_MODE" == "$SIGNING_MODE_ADHOC" ]]; then
    CODESIGN_FLAGS="$(codesign -dv "$APP_PATH" 2>&1 | grep 'flags=' || true)"
    echo "$CODESIGN_FLAGS"
    if [[ "$CODESIGN_FLAGS" == *runtime* ]]; then
        fail "ad-hoc build has the hardened runtime enabled; it will abort at launch loading Sparkle"
    fi
fi

if [[ "$SKIP_LAUNCH_CHECK" == "1" ]]; then
    echo "warning: SKIP_LAUNCH_CHECK=1; launch smoke test skipped" >&2
else
    step "Launch smoke test"
    "$APP_PATH/Contents/MacOS/$APP_NAME" &
    APP_PID=$!
    sleep "$LAUNCH_CHECK_SECONDS"
    if kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
        echo "App stayed alive for ${LAUNCH_CHECK_SECONDS}s"
    else
        wait "$APP_PID" 2>/dev/null || true
        # Crash report names are system-generated, so ls -t is safe for picking the newest.
        # shellcheck disable=SC2012
        CRASH_REPORT="$(ls -t ~/Library/Logs/DiagnosticReports/"$APP_NAME"*.ips 2>/dev/null | head -1 || true)"
        if [[ -n "$CRASH_REPORT" ]]; then
            echo "Latest crash report: $CRASH_REPORT" >&2
            # .ips files are a one-line JSON header followed by the JSON report body.
            python3 -I -c '
import json, sys
with open(sys.argv[1]) as f:
    f.readline()
    report = json.load(f)
termination = report.get("termination", {})
for key in ("namespace", "indicator", "details", "reasons"):
    if key in termination:
        print(f"{key}: {termination[key]}")
' "$CRASH_REPORT" >&2 || true
        fi
        fail "App aborted at launch; check dyld/codesign output above"
    fi
fi

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
DELTA_PATHS=()
FEED_ZIP_COUNT=0
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
        --download-url-prefix "$GITHUB_RELEASE_DOWNLOAD_URL/v$VERSION/"
        --maximum-deltas "$DELTA_PREVIOUS_VERSIONS"
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
    SEEDED=0
    HTTP_STATUS="$(curl -sSL -o "$PAGES_DIR/$APPCAST_NAME" -w '%{http_code}' "$PUBLISHED_APPCAST_URL?nocache=$(date +%s)")"
    case "$HTTP_STATUS" in
        "$HTTP_OK") echo "Seeded with published appcast from $PUBLISHED_APPCAST_URL"; SEEDED=1 ;;
        "$HTTP_NOT_FOUND") rm -f "$PAGES_DIR/$APPCAST_NAME"; echo "No published appcast yet; starting a new feed" ;;
        *) fail "fetching $PUBLISHED_APPCAST_URL returned HTTP $HTTP_STATUS; refusing to drop feed history" ;;
    esac

    # generate_appcast only builds deltas against archives that sit next to the new zip.
    PREVIOUS_ZIP_COUNT=0
    if [[ "$SEEDED" == "1" ]]; then
        PREVIOUS_ZIP_URLS=()
        while IFS= read -r PREVIOUS_URL; do
            PREVIOUS_ZIP_URLS+=("$PREVIOUS_URL")
        done < <(grep -o "url=\"$GITHUB_RELEASE_DOWNLOAD_URL/[^\"]*\.zip\"" "$PAGES_DIR/$APPCAST_NAME" | sed 's/^url="//; s/"$//' | head -n "$DELTA_PREVIOUS_VERSIONS" || true)
        PREVIOUS_ZIP_PATTERN="^$APP_NAME-([0-9][^/]*)\\.zip\$"
        for PREVIOUS_URL in ${PREVIOUS_ZIP_URLS[@]+"${PREVIOUS_ZIP_URLS[@]}"}; do
            PREVIOUS_ZIP_NAME="$(basename "$PREVIOUS_URL")"
            [[ "$PREVIOUS_ZIP_NAME" == "$ZIP_NAME" ]] && continue
            [[ "$PREVIOUS_ZIP_NAME" =~ $PREVIOUS_ZIP_PATTERN ]] || continue
            # The feed URL may point at the wrong tag, so rebuild it from the version in the file name.
            PREVIOUS_URL="$GITHUB_RELEASE_DOWNLOAD_URL/v${BASH_REMATCH[1]}/$PREVIOUS_ZIP_NAME"
            curl -fsSL -o "$APPCAST_WORK_DIR/$PREVIOUS_ZIP_NAME" "$PREVIOUS_URL" || fail "downloading previous archive $PREVIOUS_URL failed; refusing to ship without deltas"
            echo "Downloaded previous archive $PREVIOUS_ZIP_NAME for deltas"
            PREVIOUS_ZIP_COUNT=$((PREVIOUS_ZIP_COUNT + 1))
        done
    fi

    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$APPCAST_WORK_DIR"

    # generate_appcast puts every rescanned archive under the new version prefix; move each zip back to its own tag (deltas stay).
    sed -E -i '' "s#(releases/download/)v[^/\"]+/($APP_NAME-([0-9][^\"/]*)\\.zip)#\\1v\\3/\\2#g" "$PAGES_DIR/$APPCAST_NAME"
    FEED_ZIP_COUNT="$(grep -c "url=\"[^\"]*\.zip\"" "$PAGES_DIR/$APPCAST_NAME" || true)"

    for DELTA_PATH in "$APPCAST_WORK_DIR"/*.delta; do
        [[ -e "$DELTA_PATH" ]] || continue
        DELTA_PATHS+=("$DELTA_PATH")
        grep -q "$(basename "$DELTA_PATH")" "$PAGES_DIR/$APPCAST_NAME" || fail "appcast does not reference $(basename "$DELTA_PATH")"
    done
    if [[ "$PREVIOUS_ZIP_COUNT" -gt 0 && ${#DELTA_PATHS[@]} -eq 0 ]]; then
        fail "downloaded $PREVIOUS_ZIP_COUNT previous archive(s) but generate_appcast produced no deltas"
    fi
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
        echo "release_assets<<RELEASE_ASSETS_EOF"
        echo "$ZIP_PATH"
        for DELTA_PATH in ${DELTA_PATHS[@]+"${DELTA_PATHS[@]}"}; do
            echo "$DELTA_PATH"
        done
        echo "RELEASE_ASSETS_EOF"
    } >> "$GITHUB_OUTPUT"
fi

step "Summary"
echo "Version:      $VERSION ($BUILD_NUMBER)"
echo "Channel:      $CHANNEL"
echo "Signing:      $SIGNING_MODE"
echo "Notarized:    $NOTARIZED"
echo "Zip:          $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1 | tr -d ' '))"
echo "Appcast:      $APPCAST_RESULT"
DELTA_NAMES="none"
if [[ ${#DELTA_PATHS[@]} -gt 0 ]]; then
    DELTA_NAMES="$(for DELTA_PATH in "${DELTA_PATHS[@]}"; do basename "$DELTA_PATH"; done | paste -sd, - | sed 's/,/, /g')"
fi
echo "Deltas:       ${#DELTA_PATHS[@]} ($DELTA_NAMES)"
echo "Feed zips:    $FEED_ZIP_COUNT"
