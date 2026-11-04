#!/bin/sh

set -eu

ARCH=$(uname -m)
export ARCH
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/256x256/apps/com.rtsoft.patchy.png
export DESKTOP=/usr/share/applications/com.rtsoft.patchy.desktop
export DEPLOY_QML=0 # Patchy links QtQml for its JS engine only and ships no QML

# Deploy dependencies
quick-sharun \
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
