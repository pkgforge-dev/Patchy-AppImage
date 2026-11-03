#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
	cmake            \
	gettext          \
	glib2            \
	json-glib        \
	meson            \
	ninja            \
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
# Nothing is versioned here: the pins are read from the files upstream keeps them in, so a
# bump there is a bump here and a changed artifact still fails its checksum.
PATCHY_SRC="$HOME"/patchy-src
DEPS="$HOME"/patchy-deps
mkdir -p "$DEPS"

echo "Fetching the Patchy source..."
echo "---------------------------------------------------------------"
TAG=$(git ls-remote --tags --refs --sort=-v:refname \
	https://github.com/SethRobinson/Patchy.git 'v*' | head -n 1 | sed 's|.*refs/tags/||')
git clone --depth 1 --branch "$TAG" https://github.com/SethRobinson/Patchy.git "$PATCHY_SRC"
VERSION=${TAG#v}
echo "$VERSION" > ~/version

echo "Fetching ONNX Runtime and the selection models..."
echo "---------------------------------------------------------------"
# The version, the platform package and its checksum are scripts/setup-ai-deps.sh's own.
SETUP_AI="$PATCHY_SRC"/scripts/setup-ai-deps.sh
ORT_VERSION=$(sed -n 's/^ORT_VERSION="\([^"]*\)".*/\1/p' "$SETUP_AI")
ORT_PINS=$(grep "^  Linux-$ARCH)" "$SETUP_AI" || :)
ORT_PLATFORM=$(echo "$ORT_PINS" | sed -n 's/.*ORT_PLATFORM="\([^"]*\)".*/\1/p')
ORT_SHA256=$(echo "$ORT_PINS" | sed -n 's/.*ORT_SHA256="\([0-9a-f]*\)".*/\1/p')
[ -n "$ORT_VERSION" ] && [ -n "$ORT_SHA256" ] ||
	{ echo "setup-ai-deps.sh has no ONNX Runtime pins for Linux-$ARCH" >&2; exit 1; }

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

echo "Building Patchy's own GEGL bundle..."
echo "---------------------------------------------------------------"
# Built with upstream's scripts/dev/gegl/ helpers, so the bundle matches the one its
# Windows, macOS and Flatpak builds ship: babl and GEGL from the gimp.org tarballs, GEGL
# without the operations its legal review drops, staged where bundled_gegl_library() looks
# for it (<prefix>/lib/patchy/gegl). Tarballs, checksums and URLs are sources.lock's, the
# same pins the release that publishes their source uses.
PATCHY_GEGL_SCRIPTS="$PATCHY_SRC"/scripts/dev/gegl
. "$PATCHY_GEGL_SCRIPTS"/common.sh

lock_tarball() {  # <name pattern>
	awk -v p="$1" '!/^#/ && $1 ~ p { print $1; exit }' "$PATCHY_GEGL_SCRIPTS"/sources.lock
}
lock_field() {  # <tarball> <field>
	awk -v f="$1" -v c="$2" '!/^#/ && $1 == f { print $c; exit }' "$PATCHY_GEGL_SCRIPTS"/sources.lock
}

GEGL_TARBALL=$(lock_tarball '^gegl-0[.]4[.][0-9]+[.]tar[.]xz$')
BABL_TARBALL=$(lock_tarball '^babl-0[.]1[.][0-9]+[.]tar[.]xz$')
GEGL_VERSION=$(echo "$GEGL_TARBALL" | sed 's|^gegl-||; s|\.tar\.xz$||')
BABL_VERSION=$(echo "$BABL_TARBALL" | sed 's|^babl-||; s|\.tar\.xz$||')
GEGL_URL=$(lock_field "$GEGL_TARBALL" 3)
GEGL_SHA256=$(lock_field "$GEGL_TARBALL" 2)
BABL_URL=$(lock_field "$BABL_TARBALL" 3)
BABL_SHA256=$(lock_field "$BABL_TARBALL" 2)

GEGL_WORK=$(mktemp -d)
cd "$GEGL_WORK"
PREFIX="$GEGL_WORK"/install
STAGE="$DEPS"/gegl/"$GEGL_VERSION"/"$ARCH"

fetch() {  # <url> <sha256>
	file=$(basename "$1")
	curl -sSfL --retry 3 -o "$file" "$1"
	echo "$2  $file" | sha256sum -c -
	patchy_gegl_locked "$file" "$2" || { echo "$file is not in sources.lock" >&2; exit 1; }
	tar xf "$file"
}
fetch "$BABL_URL" "$BABL_SHA256"
fetch "$GEGL_URL" "$GEGL_SHA256"
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
{
	echo "Patchy's GEGL bundle ($ARCH), built $(date -u +%Y-%m-%d) by get-dependencies.sh"
	echo "GEGL $GEGL_VERSION $GEGL_URL sha256 $GEGL_SHA256"
	echo "babl $BABL_VERSION $BABL_URL sha256 $BABL_SHA256"
	echo "GLib and json-glib are the system's own and are not in this folder."
	patchy_gegl_sources_note
} > "$STAGE"/licenses/SOURCES.txt
patchy_gegl_check_sources "$STAGE"/licenses/SOURCES.txt
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
