#!/bin/sh

set -eu

ARCH=$(uname -m)
SRC=/tmp/patchy-src
DEPS=/tmp/patchy-deps

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
	cmake            \
	gettext          \
	glib2            \
	json-glib        \
	libheif          \
	meson            \
	qt6-declarative  \
	qt6-imageformats \
	qt6-svg          \
	qt6-tools        \
	qt6-translations \
	qt6-webengine

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

echo "Fetching Patchy..."
echo "---------------------------------------------------------------"
TAG=$(git ls-remote --tags --refs --sort=-v:refname https://github.com/SethRobinson/Patchy.git 'v*' |
	sed 's|.*refs/tags/||' | head -n 1)
git clone --depth 1 --branch "$TAG" https://github.com/SethRobinson/Patchy.git "$SRC"
echo "${TAG#v}" > ~/version
mkdir -p "$DEPS"
cd "$DEPS"

echo "Building Patchy's own GEGL..."
echo "---------------------------------------------------------------"
# Upstream's own helpers and pins, so the bundle is the one its Flatpak and AppImage ship
GEGL_SCRIPTS="$SRC"/scripts/dev/gegl
. "$GEGL_SCRIPTS"/common.sh
set -- $(grep -m1 '^babl-0[.]1[.].*[.]tar[.]xz ' "$GEGL_SCRIPTS"/sources.lock)
BABL=$1 BABL_SHA=$2 BABL_URL=$3
set -- $(grep -m1 '^gegl-0[.]4[.].*[.]tar[.]xz ' "$GEGL_SCRIPTS"/sources.lock)
GEGL=$1 GEGL_SHA=$2 GEGL_URL=$3
PREFIX="$DEPS"/gegl-prefix
STAGE="$DEPS"/gegl

fetch() {
	curl -sSfL --retry 3 -o "$1" "$3"
	echo "$2  $1" | sha256sum -c -
	tar xf "$1"
}
fetch "$BABL" "$BABL_SHA" "$BABL_URL"
fetch "$GEGL" "$GEGL_SHA" "$GEGL_URL"
patchy_gegl_drop_operations "${GEGL%.tar.xz}"

meson setup build-babl "${BABL%.tar.xz}" --prefix="$PREFIX" --libdir=lib --buildtype=release \
	-Dauto_features=disabled -Dwith-docs=false -Denable-gir=false -Denable-vapi=false
ninja -C build-babl install
PKG_CONFIG_PATH="$PREFIX"/lib/pkgconfig meson setup build-gegl "${GEGL%.tar.xz}" --prefix="$PREFIX" \
	--libdir=lib --buildtype=release -Dauto_features=disabled -Ddocs=false -Dworkshop=false \
	-Dintrospection=false
ninja -C build-gegl install

mkdir -p "$STAGE"/lib/gegl-0.4 "$STAGE"/lib/babl-0.1 "$STAGE"/licenses
cp -L "$PREFIX"/lib/libgegl-0.4.so.0 "$PREFIX"/lib/libbabl-0.1.so.0 "$STAGE"/lib/
for module in gegl-common gegl-common-cxx gegl-generated gegl-common-gpl3 gegl-core; do
	cp "$PREFIX"/lib/gegl-0.4/"$module"*.so "$STAGE"/lib/gegl-0.4/
done
cp "$PREFIX"/lib/babl-0.1/*.so "$STAGE"/lib/babl-0.1/
rm -f "$STAGE"/lib/babl-0.1/cairo.so
patchy_gegl_catalogs "$SRC"
patchy_gegl_license "${GEGL%.tar.xz}"/COPYING.LESSER gegl-COPYING.LESSER.txt
patchy_gegl_license "${GEGL%.tar.xz}"/COPYING gegl-COPYING.txt
patchy_gegl_license "${BABL%.tar.xz}"/COPYING babl-COPYING.txt
{
	echo "Patchy's GEGL bundle ($ARCH), built $(date -u +%Y-%m-%d) by get-dependencies.sh"
	echo "GEGL ${GEGL%.tar.xz} $GEGL_URL sha256 $GEGL_SHA"
	echo "babl ${BABL%.tar.xz} $BABL_URL sha256 $BABL_SHA"
	echo "GLib and json-glib are the system's own and are not in this folder."
	patchy_gegl_sources_note
} > "$STAGE"/licenses/SOURCES.txt
patchy_gegl_check_sources "$STAGE"/licenses/SOURCES.txt
strip --strip-unneeded "$STAGE"/lib/*.so.0 "$STAGE"/lib/*/*.so

echo "Fetching ONNX Runtime and the models..."
echo "---------------------------------------------------------------"
# The pins are upstream's own (scripts/setup-ai-deps.sh)
SETUP_AI="$SRC"/scripts/setup-ai-deps.sh
ORT_VERSION=$(sed -n 's/^ORT_VERSION="\([^"]*\)".*/\1/p' "$SETUP_AI")
ORT_PINS=$(grep "^  Linux-$ARCH)" "$SETUP_AI")
ORT_PLATFORM=$(echo "$ORT_PINS" | sed -n 's/.*ORT_PLATFORM="\([^"]*\)".*/\1/p')
ORT_SHA256=$(echo "$ORT_PINS" | sed -n 's/.*ORT_SHA256="\([0-9a-f]*\)".*/\1/p')

curl -sSfL --retry 3 -o onnxruntime.tgz \
	"https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/onnxruntime-$ORT_PLATFORM-$ORT_VERSION.tgz"
echo "$ORT_SHA256  onnxruntime.tgz" | sha256sum -c -
mkdir -p onnxruntime
tar -xf onnxruntime.tgz -C onnxruntime --strip-components=1
# Only ever dlopen'd by name, so it has to live in /usr/lib
install -Dm755 onnxruntime/lib/libonnxruntime.so."$ORT_VERSION" /usr/lib/
ln -sf libonnxruntime.so."$ORT_VERSION" /usr/lib/libonnxruntime.so.1

mkdir -p ai-models
for model in mobile_sam_image_encoder_int8.onnx sam_mask_decoder_multi_int8.onnx; do
	curl -sSfL --retry 3 -o ai-models/"$model" \
		"https://github.com/SethRobinson/Patchy/releases/download/ai-models-1/$model"
done

echo "Building Patchy..."
echo "---------------------------------------------------------------"
cmake -S "$SRC" -B build -G Ninja \
	-DCMAKE_BUILD_TYPE=Release                   \
	-DCMAKE_INSTALL_PREFIX=/usr                  \
	-DPATCHY_BUILD_TESTS=OFF                     \
	-DPATCHY_STORE_BUILD=ON                      \
	-DPATCHY_GMIC_THREADS=ON                     \
	-DPATCHY_REQUIRE_AI_SELECTION=ON             \
	-DPATCHY_REQUIRE_GEGL=ON                     \
	-DPATCHY_ONNXRUNTIME_DIR="$DEPS"/onnxruntime \
	-DPATCHY_AI_MODELS_DIR="$DEPS"/ai-models     \
	-DPATCHY_GEGL_BUNDLE_DIR="$STAGE"
cmake --build build -j"$(nproc)"
cmake --install build
