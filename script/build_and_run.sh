#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Cartograph"
BUNDLE_ID="com.cartograph.app"
PROJECT="Cartograph.xcodeproj"
SCHEME="Cartograph"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.derivedData/codex-run"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
PROJECT_FILE="$PROJECT/project.pbxproj"

usage() {
  echo "usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2
}

build_app() {
  cd "$ROOT_DIR"

  if [[ -f project.yml && ( ! -f "$PROJECT_FILE" || project.yml -nt "$PROJECT_FILE" ) ]]; then
    xcodegen generate
  fi

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    build \
    CODE_SIGNING_ALLOWED=NO
}

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\" OR process == \"$APP_NAME\""
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  *)
    usage
    exit 2
    ;;
esac
