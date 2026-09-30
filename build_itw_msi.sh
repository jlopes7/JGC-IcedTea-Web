#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "\nERROR: MSI build failed at line %s.\n" "$LINENO" >&2' ERR
trap 'popd &>/dev/null' EXIT

if (( $# > 1 )); then
    printf 'Usage: bash %s [JdkHome]\n' "$0" >&2
    exit 1
fi

JDK_ARGUMENT="${1:-C:/cygwin64/zulu8}"

export ITW_REPO
ITW_REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
pushd . &>/dev/null
cd "$ITW_REPO"

ITW_JDK_UNIX="$(cygpath -au "$JDK_ARGUMENT")"

export ITW_JDK
ITW_JDK="$(cygpath -am "$ITW_JDK_UNIX")"

export JAVA_HOME="$ITW_JDK"
export PATH="$ITW_JDK_UNIX/bin:$PATH"

export ITW_WIX_DIR="$ITW_REPO/build-deps/wix-3.14.1"
export ITW_WIXGEN_JAR="$ITW_REPO/build-deps/wixgen.jar"
export ITW_MSI_STAGE="$ITW_REPO/build-msi/image"
export ITW_DIST="$ITW_REPO/dist-native"

if [[ ! -f "$ITW_JDK_UNIX/bin/java.exe" ]]; then
    printf 'ERROR: Java executable not found under %s\n' "$ITW_JDK" >&2
    exit 1
fi

if ! [ -f "$ITW_WIX_DIR/candle.exe" ] || ! [ -f "$ITW_WIX_DIR/light.exe" ] || ! [ -f "$ITW_WIX_DIR/WixUIExtension.dll" ] || ! [ -f "$ITW_WIXGEN_JAR" ]
then	echo "[ERR] One of files required to Wix is missing. The list of required files is: $ITW_WIX_DIR/candle.exe, $ITW_WIX_DIR/light.exe, $ITW_WIX_DIR/WixUIExtension.dll and $ITW_WIXGEN_JAR" 1>&2
	exit 1
fi

bash ./autogen.sh

bash ./configure \
    --with-jdk-home="$ITW_JDK" \
    --with-itw-libs=BUNDLED \
    --with-tagsoup="$ITW_REPO/build-deps/tagsoup.jar" \
    --with-mslinks="$ITW_REPO/build-deps/mslinks.jar" \
    --with-rhino="$ITW_REPO/build-deps/js.jar" \
    --with-wix="$ITW_WIX_DIR" \
    --with-wixgen="$ITW_WIXGEN_JAR" \
    --prefix="$ITW_MSI_STAGE" \
    --disable-native-plugin \
    --disable-docs \
    --enable-shell-launchers

# Confirm configure enabled wixgen.
#if ! grep -Eq '^WIXGEN_AVAILABLE[[:space:]]*=[[:space:]]*true[[:space:]]*$' Makefile; then
#    printf 'ERROR: configure did not enable wixgen.\n' >&2
#    exit 1
#fi

# Check the distribution produced by build_itw_exe.ps1.
required_files=(
    "$ITW_DIST/bin/javaws.exe"
    "$ITW_DIST/bin/itweb-settings.exe"
    "$ITW_DIST/bin/policyeditor.exe"
    "$ITW_DIST/bin/itw-modularjdk.args"
    "$ITW_DIST/share/icedtea-web/javaws.jar"
    "$ITW_DIST/share/icedtea-web/javaws_splash.png"
    "$ITW_DIST/win-deps-runtime/tagsoup.jar"
    "$ITW_DIST/win-deps-runtime/js.jar"
    "$ITW_DIST/win-deps-runtime/mslinks.jar"
    "$ITW_REPO/javaws.ico"
    "$ITW_REPO/COPYING"
    "$ITW_REPO/win-installer/installer.json.in"
    "$ITW_REPO/win-installer/LICENSE.rtf"
    "$ITW_REPO/win-installer/icon.ico"
    "$ITW_REPO/win-installer/top_banner.bmp"
    "$ITW_REPO/win-installer/greetings_banner.bmp"
)

for file in "${required_files[@]}"; do
    if [[ ! -s "$file" ]]; then
        printf 'ERROR: Required file is missing or empty: %s\n' "$file" >&2
        printf 'Build the Java classes and Windows EXEs before packaging.\n' >&2
        exit 1
    fi
done

# The first make target cleans the previous installer outputs.
echo 'Cleaning previous MSI outputs...'
make clean-win-installer

# Remove only the dedicated MSI staging directory.
if [[ "$ITW_MSI_STAGE" != "$ITW_REPO/build-msi/image" ]]; then
    printf 'ERROR: Unexpected MSI staging directory.\n' >&2
    exit 1
fi

rm -rf -- "$ITW_MSI_STAGE"
mkdir -p "$ITW_MSI_STAGE"

echo 'Staging the Windows distribution...'
cp -a "$ITW_DIST/." "$ITW_MSI_STAGE/"

# Include the Network Rail customer files in the installation image.
mkdir -p "$ITW_MSI_STAGE/customer/NR"

cp -a "$ITW_REPO/customer/NR/." "$ITW_MSI_STAGE/customer/NR/"

# The installer registry template references this icon.
mkdir -p "$ITW_MSI_STAGE/share/pixmaps"
cp "$ITW_REPO/javaws.ico" \
   "$ITW_MSI_STAGE/share/pixmaps/javaws.ico"

# Include the repository licence in the installed distribution.
cp "$ITW_REPO/COPYING" "$ITW_MSI_STAGE/COPYING"

echo 'Generating the MSI...'

# We have already prepared the installation image from dist-native.
# Skip the upstream target that rebuilds and stages it through make install.
make --assume-old=win-only-image win-installer

shopt -s nullglob
msi_files=("$ITW_REPO"/win-installer.build/*.msi)

if (( ${#msi_files[@]} != 1 )); then
    printf 'ERROR: Expected exactly one generated MSI; found %s.\n' \
        "${#msi_files[@]}" >&2
    exit 1
fi

ITW_MSI_FILE="${msi_files[0]}"

if [[ ! -s "$ITW_MSI_FILE" ]]; then
    printf 'ERROR: Generated MSI is empty.\n' >&2
    exit 1
fi

echo -n 'MSI generated successfully:'
cygpath -aw "$ITW_MSI_FILE"

exit 0

