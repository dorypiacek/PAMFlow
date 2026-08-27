#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PAMFlow"
SCHEME="${SCHEME:-PAMFlow}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT_PATH="${PROJECT_PATH:-PAMFlow.xcodeproj}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-output/dmg}"
STAGING_ROOT="${STAGING_ROOT:-build/dmg}"
VOLUME_NAME="${VOLUME_NAME:-PAMFlow Installer}"
MIN_FREE_SPACE_GB="${MIN_FREE_SPACE_GB:-12}"
SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"
ALLOW_ADHOC_SIGNING="${ALLOW_ADHOC_SIGNING:-0}"
ENABLE_APP_SANDBOX_FOR_DMG="${ENABLE_APP_SANDBOX_FOR_DMG:-0}"
SKIP_DMG_STYLING="${SKIP_DMG_STYLING:-${CI:-0}}"
RESIGN_APP=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app}"
STAGING_DIR="$ROOT_DIR/$STAGING_ROOT/$APP_NAME"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PATH="$BACKGROUND_DIR/background.png"
DMG_PATH="$ROOT_DIR/$OUTPUT_DIR/$APP_NAME.dmg"
TEMP_DMG_PATH="$ROOT_DIR/$OUTPUT_DIR/$APP_NAME.temp.dmg"
SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/pamflow-dmg-swift-module-cache}"
APP_ICON_NAME="${APP_ICON_NAME:-AppIcon}"
SHARKTRACK_RUNTIME_DESTINATION_NAME="SharkTrackRuntime"
SHARKTRACK_RUNTIME_SOURCE="${SHARKTRACK_RUNTIME_SOURCE:-}"
SHARKTRACK_SOURCE="${SHARKTRACK_SOURCE:-}"
SHARKTRACK_VENV="${SHARKTRACK_VENV:-}"
SHARKTRACKKIT_ROOT="${SHARKTRACKKIT_ROOT:-}"
SHARKTRACK_RUNTIME_BUILD_DIR="${SHARKTRACK_RUNTIME_BUILD_DIR:-$ROOT_DIR/build/$SHARKTRACK_RUNTIME_DESTINATION_NAME}"
REMOVE_SHARKTRACK_RUNTIME_AFTER_DMG="${REMOVE_SHARKTRACK_RUNTIME_AFTER_DMG:-0}"
INSTALL_PYINSTALLER_IF_MISSING="${INSTALL_PYINSTALLER_IF_MISSING:-1}"
INSTALL_SHARKTRACK_RUNTIME_IF_MISSING="${INSTALL_SHARKTRACK_RUNTIME_IF_MISSING:-1}"
PYINSTALLER_PACKAGE="${PYINSTALLER_PACKAGE:-PyInstaller}"
if [[ -z "${PACKAGE_CONTEXT:-}" ]]; then
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        PACKAGE_CONTEXT="github"
    else
        PACKAGE_CONTEXT="local"
    fi
fi

if [[ -z "${PUSH_VERSION_TAG:-}" ]]; then
    if [[ "$PACKAGE_CONTEXT" == "github" && "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" ]]; then
        PUSH_VERSION_TAG="1"
    else
        PUSH_VERSION_TAG="0"
    fi
fi
GENERATED_SHARKTRACK_RUNTIME_SOURCE=""
RESOLVED_SIGN_IDENTITY=""

log() {
    printf '[PAMFlow DMG] %s\n' "$1"
}

fail() {
    printf '[PAMFlow DMG] Error: %s\n' "$1" >&2
    exit 1
}

available_space_gb() {
    df -g "$ROOT_DIR" | awk 'NR == 2 {print $4}'
}

resolve_sign_identity() {
    if [[ -n "$RESOLVED_SIGN_IDENTITY" ]]; then
        printf '%s\n' "$RESOLVED_SIGN_IDENTITY"
        return 0
    fi

    if [[ "$SIGN_IDENTITY" != "auto" ]]; then
        RESOLVED_SIGN_IDENTITY="$SIGN_IDENTITY"
        printf '%s\n' "$RESOLVED_SIGN_IDENTITY"
        return 0
    fi

    local identity
    identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F '"' '/Developer ID Application/ {print $2; exit}'
    )"

    if [[ -n "$identity" ]]; then
        RESOLVED_SIGN_IDENTITY="$identity"
        printf '%s\n' "$RESOLVED_SIGN_IDENTITY"
        return 0
    fi

    if [[ "$ALLOW_ADHOC_SIGNING" == "1" ]]; then
        RESOLVED_SIGN_IDENTITY='-'
        printf '%s\n' "$RESOLVED_SIGN_IDENTITY"
        return 0
    fi

    cat >&2 <<'EOF'
[PAMFlow DMG] Error: No Developer ID Application signing identity was found.

Install a Developer ID Application certificate in Keychain, or pass:

    SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

For local-only testing, opt in to an ad-hoc signature:

    ALLOW_ADHOC_SIGNING=1

Ad-hoc builds are not suitable for distribution to other users.
EOF
    exit 1
}

extract_entitlements() {
    local app_bundle="$1"
    local entitlements_path="$2"

    if /usr/bin/codesign -d --entitlements :- "$app_bundle" >"$entitlements_path" 2>/dev/null \
        && [[ -s "$entitlements_path" ]]; then
        return 0
    fi

    rm -f "$entitlements_path"
    return 1
}

add_library_validation_entitlement() {
    local entitlements_path="$1"

    if [[ ! -s "$entitlements_path" ]]; then
        cat >"$entitlements_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLIST
    fi

    /usr/libexec/PlistBuddy \
        -c 'Add :com.apple.security.cs.disable-library-validation bool true' \
        "$entitlements_path" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy \
        -c 'Set :com.apple.security.cs.disable-library-validation true' \
        "$entitlements_path" >/dev/null
}

remove_app_sandbox_entitlement_if_needed() {
    local entitlements_path="$1"

    if [[ "$ENABLE_APP_SANDBOX_FOR_DMG" == "1" ]]; then
        return 0
    fi

    /usr/libexec/PlistBuddy \
        -c 'Delete :com.apple.security.app-sandbox' \
        "$entitlements_path" >/dev/null 2>&1 || true
}

sign_code_path() {
    local identity="$1"
    local code_path="$2"
    local entitlements_path="${3:-}"

    local command=(
        /usr/bin/codesign
        --force
        --options runtime
        --timestamp=none
    )

    if [[ -n "$entitlements_path" ]]; then
        command+=(--entitlements "$entitlements_path")
    fi

    command+=(--sign "$identity" "$code_path")
    "${command[@]}"
}

require_space() {
    local available
    available="$(available_space_gb)"
    if [[ -n "$available" && "$available" -lt "$MIN_FREE_SPACE_GB" ]]; then
        cat >&2 <<EOF
Not enough free disk space to create the installer.

Available: ${available} GB
Required:  ${MIN_FREE_SPACE_GB} GB

The app bundles the SharkTrack runtime, so packaging temporarily needs enough
space for the built app, the staging folder, and the writable DMG.
EOF
        exit 1
    fi
}

create_background() {
    mkdir -p "$BACKGROUND_DIR"
    mkdir -p "$SWIFT_MODULE_CACHE_PATH"
    /usr/bin/swift -module-cache-path "$SWIFT_MODULE_CACHE_PATH" - "$BACKGROUND_PATH" <<'SWIFT'
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 640, height: 360)
let image = NSImage(size: size)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color textColor: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph
    ]
    text.draw(in: NSRect(x: x, y: y, width: 760, height: size + 12), withAttributes: attributes)
}

image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
NSColor.white.setFill()
bounds.fill()

drawText("Install PAMFlow", x: 48, y: 292, size: 28, weight: .bold, color: color(0, 0, 0))
drawText("Drag PAMFlow to Applications", x: 48, y: 258, size: 18, weight: .regular, color: color(54, 54, 54))
drawText("If macOS blocks opening, go to System Settings > Security & Privacy, scroll down, and click Open Anyway.", x: 48, y: 34, size: 13, weight: .regular, color: color(94, 94, 94))

let applicationsBox = NSBezierPath(roundedRect: NSRect(x: 418, y: 144, width: 94, height: 78), xRadius: 12, yRadius: 12)
color(0, 0, 0, 0.08).setFill()
applicationsBox.fill()
color(0, 0, 0, 0.28).setStroke()
applicationsBox.lineWidth = 2
applicationsBox.stroke()

color(0, 0, 0, 0.45).setStroke()
for offset in [CGFloat(0), CGFloat(18), CGFloat(36)] {
    let line = NSBezierPath()
    line.lineWidth = 2
    line.move(to: NSPoint(x: 438 + offset, y: 164))
    line.line(to: NSPoint(x: 458 + offset, y: 202))
    line.stroke()
}

color(0, 0, 0).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.move(to: NSPoint(x: 265, y: 171))
arrow.line(to: NSPoint(x: 375, y: 171))
arrow.stroke()
color(0, 0, 0).setFill()
let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 388, y: 171))
arrowHead.line(to: NSPoint(x: 362, y: 187))
arrowHead.line(to: NSPoint(x: 362, y: 155))
arrowHead.close()
arrowHead.fill()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    throw NSError(domain: "PAMFlowDMG", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render DMG background"])
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
SWIFT
}

find_sharktrack_runtime_source() {
    local candidate
    local candidates=(
        "$ROOT_DIR/.runtime/$SHARKTRACK_RUNTIME_DESTINATION_NAME"
        "$ROOT_DIR/build/$SHARKTRACK_RUNTIME_DESTINATION_NAME"
        "$ROOT_DIR/build/DerivedData/SourcePackages/checkouts/SharkTrackKit/.runtime/$SHARKTRACK_RUNTIME_DESTINATION_NAME"
    )

    if [[ -n "$SHARKTRACK_RUNTIME_SOURCE" ]]; then
        if [[ -d "$SHARKTRACK_RUNTIME_SOURCE" ]]; then
            printf '%s\n' "$SHARKTRACK_RUNTIME_SOURCE"
            return 0
        fi

        return 1
    fi

    for candidate in "${candidates[@]}"; do
        if is_valid_sharktrack_runtime_source "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

find_sharktrackkit_root() {
    local candidate
    local candidates=(
        "$SHARKTRACKKIT_ROOT"
        "$ROOT_DIR/build/DerivedData/SourcePackages/checkouts/SharkTrackKit"
        "/Users/dory/Documents/SharkTrackKit"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate/BuildSupport/build_runner.sh" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

default_installed_sharktrack_runtime() {
    printf '%s\n' "$HOME/Library/Application Support/SharkTrackKit/runtimes/runtime-0.1.6"
}

find_uv_bin() {
    local candidate
    local candidates=(
        "$(command -v uv 2>/dev/null || true)"
        "$HOME/Library/Application Support/SharkTrackKit/tools/uv/uv"
        "$HOME/.local/bin/uv"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

resolve_sharktrack_build_inputs() {
    local sharktrackkit_root="$1"
    local installed_runtime
    installed_runtime="$(default_installed_sharktrack_runtime)"

    if [[ -z "$SHARKTRACK_SOURCE" && ! -d "$installed_runtime/SharkTrack" && "$INSTALL_SHARKTRACK_RUNTIME_IF_MISSING" == "1" ]]; then
        log "Installing SharkTrack development runtime for packaging"
        "$sharktrackkit_root/scripts/install_runtime.sh"
    fi

    if [[ -z "$SHARKTRACK_SOURCE" && -d "$installed_runtime/SharkTrack" ]]; then
        SHARKTRACK_SOURCE="$installed_runtime/SharkTrack"
    fi

    if [[ -z "$SHARKTRACK_VENV" && -x "$installed_runtime/.venv/bin/python" ]]; then
        SHARKTRACK_VENV="$installed_runtime/.venv"
    fi

    if [[ -z "$SHARKTRACK_SOURCE" ]]; then
        fail "Could not build SharkTrack runtime automatically. Set SHARKTRACK_SOURCE to a SharkTrack source checkout."
    fi

    if [[ ! -d "$SHARKTRACK_SOURCE" ]]; then
        fail "SHARKTRACK_SOURCE does not exist: $SHARKTRACK_SOURCE"
    fi

    if [[ -z "$SHARKTRACK_VENV" ]]; then
        SHARKTRACK_VENV="$SHARKTRACK_SOURCE/.venv"
    fi

    if [[ ! -x "$SHARKTRACK_VENV/bin/python" ]]; then
        fail "Could not build SharkTrack runtime automatically. Expected Python executable at $SHARKTRACK_VENV/bin/python."
    fi
}

ensure_pyinstaller_available() {
    if "$SHARKTRACK_VENV/bin/python" -m PyInstaller --version >/dev/null 2>&1; then
        return 0
    fi

    if [[ "$INSTALL_PYINSTALLER_IF_MISSING" != "1" ]]; then
        fail "PyInstaller is not installed in $SHARKTRACK_VENV. Install it or run with INSTALL_PYINSTALLER_IF_MISSING=1."
    fi

    log "Installing PyInstaller into SharkTrack build environment"
    local uv_bin
    if uv_bin="$(find_uv_bin)"; then
        "$uv_bin" pip install --python "$SHARKTRACK_VENV/bin/python" "$PYINSTALLER_PACKAGE"
        return 0
    fi

    "$SHARKTRACK_VENV/bin/python" -m pip install "$PYINSTALLER_PACKAGE"
}

build_sharktrack_runtime() {
    local sharktrackkit_root
    local runtime_destination="$SHARKTRACK_RUNTIME_BUILD_DIR"

    if ! sharktrackkit_root="$(find_sharktrackkit_root)"; then
        fail "Could not find SharkTrackKit BuildSupport/build_runner.sh. Set SHARKTRACKKIT_ROOT=/path/to/SharkTrackKit."
    fi

    resolve_sharktrack_build_inputs "$sharktrackkit_root"
    ensure_pyinstaller_available
    log "Building frozen SharkTrack runtime"
    SHARKTRACK_SOURCE="$SHARKTRACK_SOURCE" \
    SHARKTRACK_VENV="$SHARKTRACK_VENV" \
    SHARKTRACK_RUNTIME_DEST="$runtime_destination" \
        "$sharktrackkit_root/BuildSupport/build_runner.sh"

    validate_sharktrack_runtime_source "$runtime_destination"
    GENERATED_SHARKTRACK_RUNTIME_SOURCE="$runtime_destination"
}

is_valid_sharktrack_runtime_source() {
    local runtime_source="$1"

    [[ -f "$runtime_source/.runtime-version" && -x "$runtime_source/sharktrack-runner/sharktrack-runner" ]]
}

validate_sharktrack_runtime_source() {
    local runtime_source="$1"

    if [[ ! -f "$runtime_source/.runtime-version" ]]; then
        fail "SharkTrack runtime at $runtime_source is missing .runtime-version."
    fi

    if [[ ! -x "$runtime_source/sharktrack-runner/sharktrack-runner" ]]; then
        fail "SharkTrack runtime at $runtime_source is incomplete. Expected frozen executable at sharktrack-runner/sharktrack-runner."
    fi

    return 0
}

bundle_sharktrack_runtime() {
    local app_bundle="$1"
    local runtime_source
    local runtime_destination="$app_bundle/Contents/Resources/$SHARKTRACK_RUNTIME_DESTINATION_NAME"

    if ! runtime_source="$(find_sharktrack_runtime_source)"; then
        build_sharktrack_runtime
        runtime_source="$GENERATED_SHARKTRACK_RUNTIME_SOURCE"
    fi

    validate_sharktrack_runtime_source "$runtime_source"
    log "Copying SharkTrack runtime into app bundle"
    rm -rf "$runtime_destination"
    ditto "$runtime_source" "$runtime_destination"
}

cleanup_generated_sharktrack_runtime_if_needed() {
    if [[ "$REMOVE_SHARKTRACK_RUNTIME_AFTER_DMG" != "1" ]]; then
        return 0
    fi

    if [[ -z "$GENERATED_SHARKTRACK_RUNTIME_SOURCE" ]]; then
        return 0
    fi

    log "Removing generated SharkTrack runtime"
    rm -rf "$GENERATED_SHARKTRACK_RUNTIME_SOURCE"
}

create_applications_link() {
    local staging_dir="$1"

    rm -f "$staging_dir/Applications"
    ln -s /Applications "$staging_dir/Applications"
}

ensure_app_icon() {
    local app_bundle="$1"
    local plist="$app_bundle/Contents/Info.plist"
    local assets="$app_bundle/Contents/Resources/Assets.car"

    local icon_name
    icon_name="$(
        /usr/libexec/PlistBuddy \
            -c 'Print :CFBundleIconName' \
            "$plist" 2>/dev/null || true
    )"

    if [[ "$icon_name" != "$APP_ICON_NAME" ]]; then
        fail "App icon is not configured correctly. CFBundleIconName is '$icon_name', expected '$APP_ICON_NAME'."
    fi

    if [[ ! -s "$assets" ]]; then
        fail "Compiled asset catalog is missing from $app_bundle."
    fi
}

push_version_tag_if_needed() {
    if [[ "$PUSH_VERSION_TAG" != "1" ]]; then
        return 0
    fi

    "$ROOT_DIR/scripts/push_release_tag.sh"
}

resign_app_if_needed() {
    local app_bundle="$1"
    local identity
    local entitlements_path
    local runtime_entitlements_path

    identity="$(resolve_sign_identity)"
    entitlements_path="$(mktemp "$ROOT_DIR/$STAGING_ROOT/$APP_NAME-entitlements.XXXXXX.plist")"
    runtime_entitlements_path="$(mktemp "$ROOT_DIR/$STAGING_ROOT/$APP_NAME-runtime-entitlements.XXXXXX.plist")"
    add_library_validation_entitlement "$runtime_entitlements_path"

    log "Signing with identity: $identity"

    log "Signing nested executables with hardened runtime"
    while IFS= read -r -d '' code_path; do
        sign_code_path "$identity" "$code_path"
    done < <(
        find "$app_bundle/Contents/Resources" -type f \( \
            -name '*.dylib' \
            -o -name '*.so' \
            -o -name '*.so.*' \
            -o -path '*/Python.framework/Versions/*/Python' \
            -o -name 'protoc' \
            -o -name 'torch_shm_manager' \
        \) -print0
    )

    log "Signing SharkTrack runner with library loading entitlement"
    while IFS= read -r -d '' code_path; do
        sign_code_path "$identity" "$code_path" "$runtime_entitlements_path"
    done < <(
        find "$app_bundle/Contents/Resources" -type f -name 'sharktrack-runner' -print0
    )

    log "Signing nested frameworks and bundles with hardened runtime"
    while IFS= read -r -d '' code_path; do
        sign_code_path "$identity" "$code_path"
    done < <(
        find "$app_bundle/Contents/Resources" -depth -type d \( \
            -name '*.framework' \
            -o -name '*.bundle' \
        \) -print0
    )

    if extract_entitlements "$app_bundle" "$entitlements_path"; then
        add_library_validation_entitlement "$entitlements_path"
        remove_app_sandbox_entitlement_if_needed "$entitlements_path"
        log "Signing app bundle with packaged entitlements"
        /usr/bin/codesign \
            --force \
            --options runtime \
            --timestamp=none \
            --entitlements "$entitlements_path" \
            --sign "$identity" \
            "$app_bundle"
    else
        add_library_validation_entitlement "$entitlements_path"
        remove_app_sandbox_entitlement_if_needed "$entitlements_path"
        log "Signing app bundle"
        /usr/bin/codesign \
            --force \
            --options runtime \
            --timestamp=none \
            --entitlements "$entitlements_path" \
            --sign "$identity" \
            "$app_bundle"
    fi

    rm -f "$entitlements_path" "$runtime_entitlements_path"

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
}

sign_dmg_if_needed() {
    local dmg_path="$1"
    local identity

    identity="$(resolve_sign_identity)"
    if [[ "$identity" == "-" ]]; then
        log "Skipping DMG signing for ad-hoc local build"
        return 0
    fi

    log "Signing DMG"
    /usr/bin/codesign \
        --force \
        --timestamp \
        --sign "$identity" \
        "$dmg_path"
    /usr/bin/codesign --verify --verbose=2 "$dmg_path"
}

style_dmg() {
    local mounted_volume="$1"
    local background_posix="$mounted_volume/.background/background.png"

    [[ -d "$mounted_volume/.background" ]] && /usr/bin/chflags hidden "$mounted_volume/.background"
    [[ -d "$mounted_volume/.fseventsd" ]] && /usr/bin/chflags hidden "$mounted_volume/.fseventsd"

    rm -f "$mounted_volume/Applications"
    /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    make new alias file to POSIX file "/Applications" at POSIX file "$mounted_volume" with properties {name:"Applications"}
end tell
APPLESCRIPT

    if [[ ! -s "$background_posix" ]]; then
        return 0
    fi

    /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 760, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 14
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {165, 195}
        set position of item "Applications" of container window to {465, 195}
        try
            set position of item ".background" of container window to {-500, -500}
            set visible of item ".background" of container window to false
        end try
        try
            set position of item ".fseventsd" of container window to {-500, -650}
            set visible of item ".fseventsd" of container window to false
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
}

require_space

log "Packaging context: $PACKAGE_CONTEXT"
log "Push version tag: $PUSH_VERSION_TAG"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    log "Building $APP_NAME ($CONFIGURATION)"
    xcodebuild \
        -project "$ROOT_DIR/$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$ROOT_DIR/$DERIVED_DATA_PATH" \
        -destination 'platform=macOS' \
        build
else
    log "Skipping build and packaging existing app"
fi

if [[ ! -d "$APP_PATH" ]]; then
    printf 'Expected app was not found at %s\n' "$APP_PATH" >&2
    printf 'Build first, or pass APP_PATH=/path/to/PAMFlow.app SKIP_BUILD=1.\n' >&2
    exit 1
fi

log "Preparing staging folder"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$ROOT_DIR/$OUTPUT_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
create_applications_link "$STAGING_DIR"
ensure_app_icon "$STAGING_DIR/$APP_NAME.app"
bundle_sharktrack_runtime "$STAGING_DIR/$APP_NAME.app"
resign_app_if_needed "$STAGING_DIR/$APP_NAME.app"
if [[ "$SKIP_DMG_STYLING" == "1" ]]; then
    log "Skipping DMG background for non-interactive packaging"
else
    create_background
fi

rm -f "$DMG_PATH" "$TEMP_DMG_PATH"

log "Creating temporary disk image"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$TEMP_DMG_PATH"

if [[ "$SKIP_DMG_STYLING" == "1" ]]; then
    log "Skipping Finder DMG styling for non-interactive packaging"
else
    log "Mounting disk image for Finder layout"
    MOUNT_OUTPUT="$(hdiutil attach "$TEMP_DMG_PATH" -readwrite -noverify -noautoopen)"
    MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        style_dmg "$MOUNT_POINT"
        sync
        hdiutil detach "$MOUNT_POINT" -quiet
    fi
fi

log "Compressing final DMG"
hdiutil convert "$TEMP_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TEMP_DMG_PATH"
sign_dmg_if_needed "$DMG_PATH"
cleanup_generated_sharktrack_runtime_if_needed
push_version_tag_if_needed

log "Created $DMG_PATH"
