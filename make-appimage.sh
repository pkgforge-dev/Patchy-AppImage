#!/bin/sh

set -eu

ARCH=$(uname -m)
export ARCH
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/256x256/apps/com.rtsoft.patchy.png
export DESKTOP=/usr/share/applications/com.rtsoft.patchy.desktop

# Patchy links QtQml for its JavaScript engine only and ships no QML at all
# (CMakeLists.txt, QT_QML_MODULE_NO_IMPORT_SCAN), so the QML module tree is not wanted.
export DEPLOY_QML=0

# Deploy dependencies
# libheif is only ever dlopen'd by name (HEIC), so it has to be passed explicitly.
quick-sharun                  \
	/usr/bin/patchy             \
	/usr/bin/patchy-gegl-host   \
	/usr/lib/libonnxruntime.so* \
	/usr/lib/libheif.so*        \
	/usr/lib/patchy/gegl

# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds, if the test fails due to the app
# having issues running in the CI use --simple-test instead
quick-sharun --test ./dist/*.AppImage

# And the checks a GUI launch cannot make: GEGL, ONNX Runtime and the models are only
# loaded when a filter or a selection actually runs, so the AppImage runs them itself.
export APPIMAGE_EXTRACT_AND_RUN=1
SMOKE=$(mktemp -d)
mkdir -p "$SMOKE"/settings
PATCHY_SETTINGS_DIR="$SMOKE"/settings PATCHY_NO_SOUND=1 \
	./dist/*.AppImage --headless --run-script "$HOME"/patchy-deps/gegl-smoke.js \
	--script-output "$SMOKE"/smoke.txt
test "$(tail -n 1 "$SMOKE"/smoke.txt)" = "[done]"
PATCHY_SETTINGS_DIR="$SMOKE"/settings PATCHY_NO_SOUND=1 \
	./dist/*.AppImage --mcp-connector --check
