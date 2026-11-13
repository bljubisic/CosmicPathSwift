#!/usr/bin/env bash
#
# capture-screenshots.sh — App Store screenshots for the Custom Product Pages (issue #33).
#
# Builds the Debug app once, then for each device and each page it launches the
# app with `-screenshotScene <scene>` (see CosmicPathSwift/Views/ScreenshotScene.swift).
# The app freezes the scene at its `captureMoment`; the script waits for launch
# plus that moment, and saves a screenshot to
#   AppStore/screenshots/<device>/<page>/NN-<scene>.png
# The output folder is git-ignored; rerun the script to regenerate it.
#
# Usage:
#   AppStore/capture-screenshots.sh                     # all pages, both devices
#   AppStore/capture-screenshots.sh black-holes         # one page
#   AppStore/capture-screenshots.sh --video <scene> <seconds> [device]
#                                                       # raw preview clip (.mov)
#   AppStore/capture-screenshots.sh --artwork [page]    # header (3840 × 1646) and
#                                                       # search results (3840 × 2560)
#                                                       # images for every scene, to
#                                                       # AppStore/artwork/<scene>-<asset>.png
#
# Environment overrides:
#   IPHONE_UDID  iPhone 6.3" simulator (1206 × 2622), default iPhone 17. The app's
#                listing uses the 6.1"/6.3" slot, which takes 1179 × 2556 or 1206 × 2622.
#   DEVICES      devices to capture, default "iphone ipad"
#   IPAD_UDID    iPad 13" simulator (2064 × 2752), default iPad Pro 13-inch (M5)
#   SKIP_BUILD=1 reuse the last build in AppStore/.build
#   LAUNCH_SECONDS  wait for the app's first frame (default 12)

set -euo pipefail

readonly IPHONE_UDID="${IPHONE_UDID:-8D4BD033-C1AA-4F2D-9228-E78978D124EE}"
readonly DEVICES="${DEVICES:-iphone ipad}"
readonly IPAD_UDID="${IPAD_UDID:-E6179CC9-7454-486D-9F3B-63E00BBF34B9}"
readonly BUNDLE_ID="com.persukibo.CosmicPathSwift"
readonly SCHEME="CosmicPathSwift"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(dirname "$SCRIPT_DIR")"
readonly BUILD_DIR="$SCRIPT_DIR/.build"
readonly OUTPUT_DIR="$SCRIPT_DIR/screenshots"
readonly ARTWORK_DIR="$SCRIPT_DIR/artwork"
# Artwork chosen per page, `page:asset:scene` (see AppStore/custom-product-pages.md).
# Copied to AppStore/artwork/<page>-<asset>.png, ready for App Store Connect.
readonly ARTWORK_PICKS="black-holes:header:horizonPlunge black-holes:searchResults:blackHoleVisual
three-body:header:figureEight three-body:searchResults:figureEight"
# Seconds the app needs to render and write both artwork PNGs after freezing.
readonly ARTWORK_RENDER_SECONDS=6
readonly APP_PATH="$BUILD_DIR/Build/Products/Debug-iphonesimulator/$SCHEME.app"

# Seconds the Debug app may take to show its first frame (up to ~8 s on a cold simulator).
readonly LAUNCH_SECONDS="${LAUNCH_SECONDS:-12}"

# Each page lists `scene:seconds` in App Store order. Seconds = the scene's
# `captureMoment` in ScreenshotScene.swift, rounded up (for event scenes, when
# the event has reliably happened). The script waits LAUNCH_SECONDS on top.
readonly PAGE_BLACK_HOLES="planetDisruption:22 probeRosette:8 horizonPlunge:8 blackHoleVisual:6 s2:5"
readonly PAGE_THREE_BODY="figureEight:12 threeBodyChaos:45 pythagoreanEjection:25 lagrangeBreakup:45"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

page_scenes() {
    case "$1" in
        black-holes) echo "$PAGE_BLACK_HOLES" ;;
        three-body) echo "$PAGE_THREE_BODY" ;;
        *) fail "unknown page '$1' (expected black-holes or three-body)" ;;
    esac
}

device_udid() {
    case "$1" in
        iphone) echo "$IPHONE_UDID" ;;
        ipad) echo "$IPAD_UDID" ;;
        *) fail "unknown device '$1' (expected iphone or ipad)" ;;
    esac
}

build_app() {
    if [[ "${SKIP_BUILD:-0}" == "1" && -d "$APP_PATH" ]]; then
        log "Reusing $APP_PATH"
        return
    fi
    log "Building Debug for the simulator"
    xcodebuild build -quiet \
        -project "$REPO_DIR/CosmicPathSwift.xcodeproj" \
        -scheme "$SCHEME" -configuration Debug \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$BUILD_DIR" \
        || fail "build failed"
    [[ -d "$APP_PATH" ]] || fail "no app at $APP_PATH"
}

prepare_device() {
    local udid="$1"
    log "Booting $udid"
    xcrun simctl boot "$udid" 2>/dev/null || true   # already booted is fine
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "$APP_PATH"
    xcrun simctl status_bar "$udid" override \
        --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
}

launch_scene() {
    local udid="$1" scene="$2"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$udid" "$BUNDLE_ID" -screenshotScene "$scene" "${@:3}" >/dev/null
}

capture_page() {
    local device="$1" page="$2"
    local udid index=1 entry scene delay dir file
    udid="$(device_udid "$device")"
    dir="$OUTPUT_DIR/$device/$page"
    mkdir -p "$dir"
    for entry in $(page_scenes "$page"); do
        scene="${entry%%:*}"
        delay="${entry##*:}"
        file="$dir/$(printf '%02d' "$index")-$scene.png"
        log "$device / $page: $scene (frozen after ~${delay}s)"
        launch_scene "$udid" "$scene"
        sleep $((LAUNCH_SECONDS + delay))
        xcrun simctl io "$udid" screenshot --type=png "$file" >/dev/null
        index=$((index + 1))
    done
}

record_video() {
    local scene="$1" seconds="$2" device="${3:-iphone}"
    local udid file pid
    udid="$(device_udid "$device")"
    [[ "$seconds" =~ ^[0-9]+$ ]] || fail "seconds must be a whole number"
    build_app
    prepare_device "$udid"
    mkdir -p "$OUTPUT_DIR/$device/video"
    file="$OUTPUT_DIR/$device/video/$scene.mov"
    # Recording starts before launch so the scene's first frames are in the
    # clip; trim the launch screen off the start when editing the preview.
    log "Recording $scene for ${seconds}s after launch on $device"
    xcrun simctl io "$udid" recordVideo --codec=h264 --force "$file" &
    pid=$!
    sleep 1
    launch_scene "$udid" "$scene" -screenshotRecording YES
    sleep $((LAUNCH_SECONDS + seconds))
    kill -INT "$pid"
    wait "$pid" || true
    log "Saved $file"
}

copy_artwork_picks() {
    local pick page asset scene source
    for pick in $ARTWORK_PICKS; do
        IFS=: read -r page asset scene <<< "$pick"
        source="$ARTWORK_DIR/$scene-$asset.png"
        [[ -f "$source" ]] || continue   # page not rendered in this run
        cp "$source" "$ARTWORK_DIR/$page-$asset.png"
        log "$page $asset: $scene"
    done
}

render_artwork() {
    local pages=("$@") udid page entry scene delay container
    [[ ${#pages[@]} -gt 0 ]] || pages=(black-holes three-body)
    udid="$IPHONE_UDID"   # any device: the canvas is re-rendered at the asset sizes
    build_app
    prepare_device "$udid"
    container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)"
    [[ -n "$container" && -d "$container" ]] || fail "no data container for $BUNDLE_ID"
    mkdir -p "$ARTWORK_DIR"
    for page in "${pages[@]}"; do
        for entry in $(page_scenes "$page"); do
            scene="${entry%%:*}"
            delay="${entry##*:}"
            log "artwork: $scene (frozen after ~${delay}s)"
            rm -f "$container/Documents/artwork/$scene-"*.png
            launch_scene "$udid" "$scene" -artworkExport YES
            sleep $((LAUNCH_SECONDS + delay + ARTWORK_RENDER_SECONDS))
            cp "$container/Documents/artwork/$scene-"*.png "$ARTWORK_DIR/" \
                || fail "no artwork for $scene (render may need more time)"
        done
    done
    copy_artwork_picks
    log "Artwork in $ARTWORK_DIR"
}

main() {
    if [[ "${1:-}" == "--artwork" ]]; then
        shift
        render_artwork "$@"
        return
    fi
    if [[ "${1:-}" == "--video" ]]; then
        [[ $# -ge 3 ]] || fail "usage: $0 --video <scene> <seconds> [iphone|ipad]"
        record_video "$2" "$3" "${4:-iphone}"
        return
    fi
    local pages=("${@:-black-holes three-body}")
    # shellcheck disable=SC2206  # intentional word splitting of the default list
    pages=(${pages[*]})
    build_app
    for device in $DEVICES; do
        prepare_device "$(device_udid "$device")"
        for page in "${pages[@]}"; do
            capture_page "$device" "$page"
        done
        xcrun simctl status_bar "$(device_udid "$device")" clear
    done
    log "Screenshots in $OUTPUT_DIR"
}

main "$@"
