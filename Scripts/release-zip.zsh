#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SeedBox.xcodeproj"
SCHEME="${SEEDBOX_RELEASE_SCHEME:-Seed Box}"
CONFIGURATION="${SEEDBOX_RELEASE_CONFIGURATION:-Release}"
APP_BUNDLE_NAME="Seed Box Mod Manager"
RELEASE_NAME="${SEEDBOX_RELEASE_NAME:-SeedBox}"
RELEASE_CHANNEL="${SEEDBOX_RELEASE_CHANNEL:-app-store-candidate}"
TEAM_ID="${SEEDBOX_TEAM_ID:-PUT2KYMV2W}"
NOTARY_PROFILE="${SEEDBOX_NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${SEEDBOX_NOTARY_APPLE_ID:-}"
NOTARY_PASSWORD="${SEEDBOX_NOTARY_PASSWORD:-}"
OUTPUT_DIR="$ROOT_DIR/dist"
RELEASE_TMP_ROOT="${TMPDIR:-/private/tmp}"
WORK_DIR="${SEEDBOX_RELEASE_WORK_DIR:-${RELEASE_TMP_ROOT%/}/seedbox-release-${USER:-user}-zip}"
ARCHIVE_PATH="${SEEDBOX_ARCHIVE_PATH:-}"
REUSE_ARCHIVE=false
SKIP_NOTARIZATION=false
typeset -a NOTARY_ARGS

usage() {
    cat <<'USAGE'
Usage: Scripts/release-zip.zsh [options]

Archive, export, notarize, staple, package, and verify a Seed Box release ZIP.
The archive/export steps use Xcode's Developer ID export path so Xcode handles
the app bundle, Swift runtime, SwiftPM frameworks, signing, and entitlements.

Options:
  --steam                   Build the Steam-compatible Developer ID ZIP.
  --archive-path PATH       Reuse an existing .xcarchive instead of archiving.
  --skip-notarization       Export and package without submitting to Apple.
  --notary-profile NAME     notarytool keychain profile name.
  --team-id TEAMID          Apple Developer Team ID.
  --output-dir PATH         Directory for the final ZIP. Defaults to ./dist.
  -h, --help                Show this help.

Environment variables:
  SEEDBOX_RELEASE_CHANNEL
  SEEDBOX_RELEASE_CONFIGURATION
  SEEDBOX_RELEASE_NAME
  SEEDBOX_RELEASE_SCHEME
  SEEDBOX_TEAM_ID
  SEEDBOX_ARCHIVE_PATH
  SEEDBOX_NOTARY_PROFILE
  SEEDBOX_NOTARY_APPLE_ID
  SEEDBOX_NOTARY_PASSWORD
  SEEDBOX_RELEASE_WORK_DIR

Notarization requires either a notarytool keychain profile or Apple ID
credentials in the environment. Prefer SEEDBOX_NOTARY_PROFILE for local use.
USAGE
}

require_command() {
    local command_path="$1"

    if [[ -x "$command_path" ]]; then
        return 0
    fi

    echo "ERROR: Missing required command: $command_path"
    exit 1
}

require_value() {
    local name="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "ERROR: Missing required value: $name"
        exit 1
    fi
}

apply_release_channel_defaults() {
    case "$RELEASE_CHANNEL" in
        app-store-candidate)
            ;;
        steam)
            if [[ -z "${SEEDBOX_RELEASE_SCHEME:-}" ]]; then
                SCHEME="Seed Box Steam"
            fi
            if [[ -z "${SEEDBOX_RELEASE_CONFIGURATION:-}" ]]; then
                CONFIGURATION="Release Steam"
            fi
            if [[ -z "${SEEDBOX_RELEASE_NAME:-}" ]]; then
                RELEASE_NAME="SeedBox-Steam"
            fi
            ;;
        *)
            echo "ERROR: Unknown release channel: $RELEASE_CHANNEL"
            exit 64
            ;;
    esac
}

refuse_unsafe_path() {
    local path_to_check="${1:A}"
    local label="$2"
    local unsafe_root="${3:-}"

    case "$path_to_check" in
        "/"|"$HOME")
            echo "ERROR: Refusing to use unsafe $label: $path_to_check"
            exit 1
            ;;
    esac

    if [[ -z "$unsafe_root" ]]; then
        return 0
    fi

    local unsafe_root_path="${unsafe_root:A}"
    case "$path_to_check" in
        "$unsafe_root_path"|"$unsafe_root_path"/*)
            echo "ERROR: Refusing to use unsafe $label: $path_to_check"
            exit 1
            ;;
    esac
}

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

json_string() {
    local value="$1"

    printf '"%s"' "$(json_escape "$value")"
}

write_release_manifest() {
    local manifest_path="$1"
    local version="$2"
    local build="$3"
    local bundle_identifier="$4"
    local app_path="$5"
    local zip_path="$6"
    local notarized="$7"
    local zip_name
    local zip_sha256
    local generated_at

    zip_name="$(basename "$zip_path")"
    zip_sha256="$(/usr/bin/shasum -a 256 "$zip_path" | /usr/bin/awk '{print $1}')"
    generated_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"

    cat > "$manifest_path" <<EOF
{
  "appName": $(json_string "$APP_BUNDLE_NAME"),
  "releaseName": $(json_string "$RELEASE_NAME"),
  "version": $(json_string "$version"),
  "build": $(json_string "$build"),
  "bundleIdentifier": $(json_string "$bundle_identifier"),
  "teamID": $(json_string "$TEAM_ID"),
  "archivePath": $(json_string "$ARCHIVE_PATH"),
  "appPath": $(json_string "$app_path"),
  "zipName": $(json_string "$zip_name"),
  "zipPath": $(json_string "$zip_path"),
  "zipSHA256": $(json_string "$zip_sha256"),
  "notarized": $notarized,
  "generatedAt": $(json_string "$generated_at")
}
EOF
}

write_export_options() {
    local export_options_path="$1"

    cat > "$export_options_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF
}

find_exported_app() {
    local export_path="$1"
    local app_path

    app_path="$(/usr/bin/find "$export_path" -maxdepth 3 -name "$APP_BUNDLE_NAME.app" -type d -print -quit)"
    if [[ -z "$app_path" ]]; then
        app_path="$(/usr/bin/find "$export_path" -maxdepth 3 -name "*.app" -type d -print -quit)"
    fi

    if [[ -z "$app_path" ]]; then
        echo "ERROR: Could not find an exported app in $export_path"
        exit 1
    fi

    echo "$app_path"
}

extract_app_from_zip() {
    local zip_path="$1"
    local destination_path="$2"
    local app_path

    /bin/rm -rf "$destination_path"
    /bin/mkdir -p "$destination_path"
    /usr/bin/ditto -x -k "$zip_path" "$destination_path"

    app_path="$(/usr/bin/find "$destination_path" -maxdepth 3 -name "$APP_BUNDLE_NAME.app" -type d -print -quit)"
    if [[ -z "$app_path" ]]; then
        app_path="$(/usr/bin/find "$destination_path" -maxdepth 3 -name "*.app" -type d -print -quit)"
    fi

    if [[ -z "$app_path" ]]; then
        echo "ERROR: Could not find an app after extracting $zip_path"
        exit 1
    fi

    echo "$app_path"
}

codesign_entitlements() {
    local target_path="$1"
    local output_path="$2"

    /usr/bin/codesign -d --entitlements - "$target_path" > "$output_path" 2>/dev/null
}

assert_entitlement_present() {
    local entitlements_path="$1"
    local entitlement="$2"

    if ! /usr/bin/grep -q "$entitlement" "$entitlements_path"; then
        echo "ERROR: Missing expected entitlement: $entitlement"
        echo "$entitlements_path"
        exit 1
    fi
}

assert_entitlement_absent() {
    local entitlements_path="$1"
    local entitlement="$2"

    if /usr/bin/grep -q "$entitlement" "$entitlements_path"; then
        echo "ERROR: Found unwanted entitlement: $entitlement"
        echo "$entitlements_path"
        exit 1
    fi
}

archive_app() {
    echo ""
    echo "Archiving with Xcode..."
    /usr/bin/xcodebuild archive \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_PATH" \
        -derivedDataPath "$WORK_DIR/DerivedData" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO
}

export_archive() {
    local export_options_path="$1"
    local export_path="$2"

    echo ""
    echo "Exporting Developer ID app..."
    /bin/rm -rf "$export_path"
    /usr/bin/xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options_path"
}

verify_signed_app() {
    local app_path="$1"
    local bundle_identifier="$2"
    local entitlements_path="$3"
    local signature_path="$4"

    echo ""
    echo "Verifying app signature and entitlements..."
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
    /usr/bin/codesign -dv --verbose=4 "$app_path" > "$signature_path" 2>&1

    if ! /usr/bin/grep -q "Authority=Developer ID Application" "$signature_path"; then
        echo "ERROR: Exported app is not signed with a Developer ID Application certificate."
        echo "$signature_path"
        exit 1
    fi

    if ! /usr/bin/grep -q "TeamIdentifier=$TEAM_ID" "$signature_path"; then
        echo "ERROR: Exported app is not signed by the expected team: $TEAM_ID"
        echo "$signature_path"
        exit 1
    fi

    codesign_entitlements "$app_path" "$entitlements_path"
    case "$RELEASE_CHANNEL" in
        app-store-candidate)
            assert_entitlement_present "$entitlements_path" "com.apple.security.app-sandbox"
            assert_entitlement_present "$entitlements_path" "com.apple.security.files.bookmarks.app-scope"
            assert_entitlement_present "$entitlements_path" "com.apple.security.files.user-selected.read-write"
            assert_entitlement_present "$entitlements_path" "com.apple.security.network.client"
            ;;
        steam)
            assert_entitlement_absent "$entitlements_path" "com.apple.security.app-sandbox"
            assert_entitlement_absent "$entitlements_path" "com.apple.security.cs.allow-dyld-environment-variables"
            assert_entitlement_absent "$entitlements_path" "com.apple.security.cs.disable-library-validation"
            ;;
    esac
    assert_entitlement_absent "$entitlements_path" "com.apple.security.get-task-allow"
    assert_entitlement_absent "$entitlements_path" "PRODUCT_BUNDLE_IDENTIFIER"

    if [[ "$bundle_identifier" != "com.fahlsing.SeedBox" ]]; then
        echo "ERROR: Unexpected bundle identifier: $bundle_identifier"
        exit 1
    fi
}

verify_app_architecture() {
    local app_path="$1"
    local executable_path="$app_path/Contents/MacOS/SeedBox"
    local file_output

    echo ""
    echo "Verifying app architecture..."
    file_output="$(/usr/bin/file "$executable_path")"
    echo "$file_output"

    for expected_arch in arm64 x86_64; do
        if [[ "$file_output" != *"$expected_arch"* ]]; then
            echo "ERROR: App executable is missing $expected_arch."
            exit 1
        fi
    done
}

run_gatekeeper_zip_check() {
    local zip_path="$1"
    local gatekeeper_dir="$2"
    local extracted_app_path

    echo ""
    echo "Assessing final ZIP with a local quarantine Gatekeeper check..."
    extracted_app_path="$(extract_app_from_zip "$zip_path" "$gatekeeper_dir")"
    /usr/bin/xattr -r -w com.apple.quarantine "0081;00000000;SeedBox;https://github.com/fahlman/SeedBox" "$extracted_app_path"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$extracted_app_path"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --steam)
            RELEASE_CHANNEL=steam
            shift
            ;;
        --archive-path)
            ARCHIVE_PATH="${2:-}"
            REUSE_ARCHIVE=true
            shift 2
            ;;
        --skip-notarization)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --notary-profile)
            NOTARY_PROFILE="${2:-}"
            shift 2
            ;;
        --team-id)
            TEAM_ID="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo ""
            usage
            exit 64
            ;;
    esac
done

apply_release_channel_defaults
require_value "TEAM_ID" "$TEAM_ID"
require_command /usr/bin/awk
require_command /usr/bin/codesign
require_command /usr/bin/ditto
require_command /usr/bin/file
require_command /usr/bin/find
require_command /usr/bin/plutil
require_command /usr/bin/shasum
require_command /usr/bin/xattr
require_command /usr/bin/xcodebuild
require_command /usr/bin/xcrun
require_command /usr/sbin/spctl

if [[ "$SKIP_NOTARIZATION" == false ]]; then
    if [[ -n "$NOTARY_PROFILE" ]]; then
        NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    elif [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_PASSWORD" ]]; then
        NOTARY_ARGS=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$TEAM_ID")
    else
        echo "ERROR: Notarization needs --notary-profile or SEEDBOX_NOTARY_PROFILE."
        echo "Use --skip-notarization for a Developer ID export check without Apple notarization."
        exit 1
    fi
fi

refuse_unsafe_path "$WORK_DIR" "release work directory" "$ROOT_DIR"

if [[ -n "$ARCHIVE_PATH" ]]; then
    REUSE_ARCHIVE=true
else
    ARCHIVE_PATH="$WORK_DIR/$APP_BUNDLE_NAME.xcarchive"
fi

EXPORT_OPTIONS_PATH="$WORK_DIR/ExportOptions.plist"
EXPORT_PATH="$WORK_DIR/export"
NOTARY_ZIP_PATH="$WORK_DIR/$RELEASE_NAME-notary.zip"
GATEKEEPER_CHECK_PATH="$WORK_DIR/gatekeeper-check"
APP_ENTITLEMENTS_PATH="$WORK_DIR/$RELEASE_NAME.entitlements"
SIGNATURE_PATH="$WORK_DIR/$RELEASE_NAME-signature.txt"

echo "Seed Box ZIP release"
echo "Root:        $ROOT_DIR"
echo "Channel:     $RELEASE_CHANNEL"
echo "Scheme:      $SCHEME"
echo "Config:      $CONFIGURATION"
echo "Team ID:     $TEAM_ID"
echo "Archive:     $ARCHIVE_PATH"
echo "Work dir:    $WORK_DIR"
echo "Output:      $OUTPUT_DIR"

/bin/mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
write_export_options "$EXPORT_OPTIONS_PATH"

if [[ "$REUSE_ARCHIVE" == true ]]; then
    if [[ ! -d "$ARCHIVE_PATH" ]]; then
        echo "ERROR: Archive path does not exist: $ARCHIVE_PATH"
        exit 1
    fi
    
    echo ""
    echo "Using existing archive:"
    echo "$ARCHIVE_PATH"
else
    /bin/rm -rf "$ARCHIVE_PATH"
    archive_app
fi

export_archive "$EXPORT_OPTIONS_PATH" "$EXPORT_PATH"

APP_PATH="$(find_exported_app "$EXPORT_PATH")"
/usr/bin/xattr -cr "$APP_PATH"

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$APP_PATH/Contents/Info.plist")"
BUNDLE_IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist")"
ZIP_PATH="$OUTPUT_DIR/$RELEASE_NAME-$VERSION.zip"
MANIFEST_PATH="$OUTPUT_DIR/$RELEASE_NAME-$VERSION-manifest.json"

verify_signed_app "$APP_PATH" "$BUNDLE_IDENTIFIER" "$APP_ENTITLEMENTS_PATH" "$SIGNATURE_PATH"
verify_app_architecture "$APP_PATH"

/bin/rm -f "$ZIP_PATH" "$NOTARY_ZIP_PATH"

echo ""
echo "Creating notarization ZIP..."
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"

if [[ "$SKIP_NOTARIZATION" == true ]]; then
    /bin/cp "$NOTARY_ZIP_PATH" "$ZIP_PATH"
    write_release_manifest "$MANIFEST_PATH" "$VERSION" "$BUILD" "$BUNDLE_IDENTIFIER" "$APP_PATH" "$ZIP_PATH" false
    echo ""
    echo "Skipped notarization."
    echo "ZIP: $ZIP_PATH"
    echo "Manifest: $MANIFEST_PATH"
    exit 0
fi

echo ""
echo "Submitting ZIP for notarization..."
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP_PATH" --wait "${NOTARY_ARGS[@]}"

echo ""
echo "Stapling notarization ticket to app..."
/usr/bin/xcrun stapler staple "$APP_PATH"
/usr/bin/xcrun stapler validate "$APP_PATH"

echo ""
echo "Assessing notarized app with Gatekeeper..."
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_PATH"

echo ""
echo "Creating final ZIP..."
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

run_gatekeeper_zip_check "$ZIP_PATH" "$GATEKEEPER_CHECK_PATH"
write_release_manifest "$MANIFEST_PATH" "$VERSION" "$BUILD" "$BUNDLE_IDENTIFIER" "$APP_PATH" "$ZIP_PATH" true

echo ""
echo "Release ZIP is ready:"
echo "$ZIP_PATH"
echo "Release manifest:"
echo "$MANIFEST_PATH"
