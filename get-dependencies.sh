#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
	base-devel       \
	cmake            \
	gettext          \
	git              \
	glib2            \
	json-glib        \
	meson            \
	ninja            \
	python           \
	qt6-base         \
	qt6-declarative  \
	qt6-imageformats \
	qt6-svg          \
	qt6-tools        \
	qt6-translations \
	qt6-webengine

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

# Patchy ships no distro package, so it is built from source here, along with the three
# things it loads at run time and never links: its own GEGL bundle, ONNX Runtime and the
# selection models (upstream builds all of them for its Flatpak and its own AppImage).
PATCHY_SRC="$HOME"/patchy-src
DEPS="$HOME"/patchy-deps
BABL_VERSION=0.1.128
GEGL_VERSION=0.4.72
ORT_VERSION=1.30.0

case "$ARCH" in
	x86_64)
		GEGL_PLATFORM=linux-x64
		ORT_PLATFORM=linux-x64
		ORT_SHA256=a5ed5a3cac51fbb2e90da632ae43d19212faaa20e76484e62bcb7c23ddb3b3fd
		;;
	aarch64)
		GEGL_PLATFORM=linux-aarch64
		ORT_PLATFORM=linux-aarch64
		ORT_SHA256=e16a27a8ed330bbc698df7330b0cf56e722f354e3bcc92118682c74ef3c3e3da
		;;
	*)
		echo "Unsupported architecture: $ARCH" >&2
		exit 1
		;;
esac

mkdir -p "$DEPS"

echo "Fetching the Patchy source..."
echo "---------------------------------------------------------------"
if [ "${DEVEL_RELEASE-}" = 1 ]; then
	git clone --depth 1 https://github.com/SethRobinson/Patchy.git "$PATCHY_SRC"
	VERSION=$(date -u +%Y%m%d)
else
	TAG=$(git ls-remote --tags --refs --sort=-v:refname \
		https://github.com/SethRobinson/Patchy.git 'v*' | head -n 1 | sed 's|.*refs/tags/||')
	git clone --depth 1 --branch "$TAG" https://github.com/SethRobinson/Patchy.git "$PATCHY_SRC"
	VERSION=${TAG#v}
fi
echo "$VERSION" > ~/version

echo "Fetching ONNX Runtime $ORT_VERSION and the selection models..."
echo "---------------------------------------------------------------"
# The library is only ever dlopen'd, by file name, so it has to sit in /usr/lib: nothing
# links it, which means quick-sharun cannot find it on its own.
curl -sSfL --retry 3 -o "$DEPS"/onnxruntime.tgz \
	"https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/onnxruntime-$ORT_PLATFORM-$ORT_VERSION.tgz"
echo "$ORT_SHA256  $DEPS/onnxruntime.tgz" | sha256sum -c -
ORT_DIR="$DEPS"/onnxruntime/"$ORT_VERSION"/"$ORT_PLATFORM"
mkdir -p "$ORT_DIR"
tar -xf "$DEPS"/onnxruntime.tgz -C "$ORT_DIR" --strip-components=1
rm -f "$DEPS"/onnxruntime.tgz
install -Dm755 "$ORT_DIR"/lib/libonnxruntime.so."$ORT_VERSION" /usr/lib/libonnxruntime.so."$ORT_VERSION"
ln -sf libonnxruntime.so."$ORT_VERSION" /usr/lib/libonnxruntime.so.1

# The two models every build bundles; the higher quality ones are downloaded in the app.
# Same pinned files and checksums as scripts/setup-ai-deps.sh, minus its dev extras.
mkdir -p "$DEPS"/ai-models
while IFS='|' read -r model url sha256; do
	curl -sSfL --retry 3 -o "$DEPS"/ai-models/"$model" "$url"
	echo "$sha256  $DEPS/ai-models/$model" | sha256sum -c -
done <<-EOF
	mobile_sam_image_encoder_int8.onnx|https://github.com/SethRobinson/Patchy/releases/download/ai-models-1/mobile_sam_image_encoder_int8.onnx|6af3f249f7a5a6a8a3ef988b6814015e8c3a300977c135d1f9572ed2f2930cd7
	sam_mask_decoder_multi_int8.onnx|https://github.com/SethRobinson/Patchy/releases/download/ai-models-1/sam_mask_decoder_multi_int8.onnx|aa1410bec8f050b6017fba29ca07f16317029a8f74a98e5998aeed46680c10a6
EOF

echo "Building Patchy's own GEGL $GEGL_VERSION bundle..."
echo "---------------------------------------------------------------"
# Built with upstream's scripts/dev/gegl/ helpers, so the bundle matches the one its
# Windows, macOS and Flatpak builds ship: babl and GEGL from the gimp.org tarballs, GEGL
# without the operations its legal review drops, staged where bundled_gegl_library() looks
# for it (<prefix>/lib/patchy/gegl).
PATCHY_GEGL_SCRIPTS="$PATCHY_SRC"/scripts/dev/gegl
. "$PATCHY_GEGL_SCRIPTS"/common.sh
GEGL_WORK=$(mktemp -d)
cd "$GEGL_WORK"
PREFIX="$GEGL_WORK"/install
STAGE="$DEPS"/gegl/"$GEGL_VERSION"/"$GEGL_PLATFORM"

fetch() {
	curl -sSfL --retry 3 -o "$(basename "$1")" "$1"
	echo "$2  $(basename "$1")" | sha256sum -c -
	patchy_gegl_locked "$(basename "$1")" "$2"
	tar xf "$(basename "$1")"
}
fetch "https://download.gimp.org/pub/babl/0.1/babl-$BABL_VERSION.tar.xz" \
	e676507b421d414d49db8627415dc1eadbd787536baa7d6fe94a1f1971cbe73e
fetch "https://download.gimp.org/pub/gegl/0.4/gegl-$GEGL_VERSION.tar.xz" \
	ccbb8cdd1db56ecd4ece5dbabae0118ab2c46b5b3439c94f3cec467798ce956d
patchy_gegl_drop_operations "gegl-$GEGL_VERSION"

meson setup build-babl "babl-$BABL_VERSION" --prefix="$PREFIX" --libdir=lib \
	--buildtype=release -Dauto_features=disabled -Dwith-docs=false \
	-Denable-gir=false -Denable-vapi=false
ninja -C build-babl install
PKG_CONFIG_PATH="$PREFIX"/lib/pkgconfig meson setup build-gegl "gegl-$GEGL_VERSION" \
	--prefix="$PREFIX" --libdir=lib --buildtype=release -Dauto_features=disabled \
	-Ddocs=false -Dworkshop=false -Dintrospection=false
ninja -C build-gegl install

mkdir -p "$STAGE"/lib/gegl-0.4 "$STAGE"/lib/babl-0.1 "$STAGE"/licenses
cp -L "$PREFIX"/lib/libgegl-0.4.so.0 "$PREFIX"/lib/libbabl-0.1.so.0 "$STAGE"/lib/
for module in gegl-common gegl-common-cxx gegl-generated gegl-common-gpl3 gegl-core; do
	for file in "$PREFIX"/lib/gegl-0.4/"$module".so "$PREFIX"/lib/gegl-0.4/"$module"-*.so; do
		if [ -f "$file" ]; then
			cp "$file" "$STAGE"/lib/gegl-0.4/
		fi
	done
done
cp "$PREFIX"/lib/babl-0.1/*.so "$STAGE"/lib/babl-0.1/
rm -f "$STAGE"/lib/babl-0.1/cairo.so
patchy_gegl_catalogs "$PATCHY_SRC"
patchy_gegl_license "gegl-$GEGL_VERSION"/COPYING.LESSER gegl-COPYING.LESSER.txt
patchy_gegl_license "gegl-$GEGL_VERSION"/COPYING gegl-COPYING.txt
patchy_gegl_license "babl-$BABL_VERSION"/COPYING babl-COPYING.txt
patchy_gegl_sources_note > "$STAGE"/licenses/SOURCES.txt
strip --strip-unneeded "$STAGE"/lib/*.so.0 "$STAGE"/lib/gegl-0.4/*.so \
	"$STAGE"/lib/babl-0.1/*.so
cd "$HOME"
rm -rf "$GEGL_WORK"

echo "Building Patchy $VERSION..."
echo "---------------------------------------------------------------"
# PATCHY_STORE_BUILD: this package delivers its own updates through the self-updater hook,
# so the in-app updater must not offer to replace the AppImage with upstream's.
cmake -S "$PATCHY_SRC" -B "$PATCHY_SRC"/build -G Ninja \
	-DCMAKE_BUILD_TYPE=Release               \
	-DCMAKE_INSTALL_PREFIX=/usr              \
	-DPATCHY_BUILD_TESTS=OFF                 \
	-DPATCHY_STORE_BUILD=ON                  \
	-DPATCHY_GMIC_THREADS=ON                 \
	-DPATCHY_REQUIRE_AI_SELECTION=ON         \
	-DPATCHY_REQUIRE_GEGL=ON                 \
	-DPATCHY_ONNXRUNTIME_DIR="$ORT_DIR"      \
	-DPATCHY_AI_MODELS_DIR="$DEPS"/ai-models \
	-DPATCHY_GEGL_BUNDLE_DIR="$STAGE"
cmake --build "$PATCHY_SRC"/build -j"$(nproc)"

cmake --install "$PATCHY_SRC"/build

echo "Running Patchy's headless checks..."
echo "---------------------------------------------------------------"
# The GEGL bundle and the models only load at run time, so this is what proves the bundle
# layout and the model install. The smoke script is kept beside the deps for
# make-appimage.sh, which repeats both checks against the AppImage itself.
cp "$PATCHY_SRC"/packaging/gegl-smoke.js "$DEPS"/gegl-smoke.js
SMOKE=$(mktemp -d)
mkdir -p "$SMOKE"/settings
PATCHY_SETTINGS_DIR="$SMOKE"/settings PATCHY_NO_SOUND=1 \
	patchy --headless --run-script "$DEPS"/gegl-smoke.js --script-output "$SMOKE"/smoke.txt
test "$(tail -n 1 "$SMOKE"/smoke.txt)" = "[done]"
PATCHY_SETTINGS_DIR="$SMOKE"/settings patchy --mcp-connector --check
rm -rf "$SMOKE"
