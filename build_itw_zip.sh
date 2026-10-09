#!/usr/bin/env bash
# Package the existing Windows distribution using the MSI's installed layout.
# Run in Cygwin: bash build_itw_zip.sh [OutputZip]
# Relative output paths are resolved from the directory containing this script.
# No Java/Rust compilation, signing, WiX, or JDK is required.
set -Eeuo pipefail

trap 'printf "\nERROR: ZIP packaging failed at line %s.\n" "$LINENO" >&2' ERR

if (( $# > 1 )); then
    printf 'Usage: bash %s [OutputZip]\n' "$0" >&2
    exit 1
fi

ITW_REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ITW_DIST="$ITW_REPO/dist-native"
ITW_CUSTOMER="$ITW_REPO/customer/NR"
ITW_CLASSES_JAR="$ITW_REPO/netx.build/lib/classes.jar"

# Match the MSI layout. Use existing dist-native launchers and resources,
# and refresh javaws.jar from the compiled JAR used by build_itw_exe.ps1.
required_files=(
    "$ITW_CLASSES_JAR"
    "$ITW_DIST/bin/javaws.exe"
    "$ITW_DIST/bin/itweb-settings.exe"
    "$ITW_DIST/bin/policyeditor.exe"
    "$ITW_DIST/bin/itw-modularjdk.args"
    "$ITW_DIST/share/icedtea-web/javaws_splash.png"
    "$ITW_DIST/win-deps-runtime/tagsoup.jar"
    "$ITW_DIST/win-deps-runtime/js.jar"
    "$ITW_DIST/win-deps-runtime/mslinks.jar"
    "$ITW_REPO/javaws.ico"
    "$ITW_REPO/COPYING"
)

for file in "${required_files[@]}"; do
    if [[ ! -s "$file" ]]; then
        printf 'ERROR: Required file is missing or empty: %s\n' "$file" >&2
        printf 'Prepare the Java classes and Windows EXEs before packaging.\n' >&2
        exit 1
    fi
done

if [[ ! -d "$ITW_CUSTOMER" ]]; then
    printf 'ERROR: Customer directory is missing: %s\n' "$ITW_CUSTOMER" >&2
    exit 1
fi

# Prefer Cygwin zip/unzip. Windows PowerShell is a dependency-free fallback.
if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
    ZIP_BACKEND=zip
elif command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    ZIP_BACKEND=powershell
else
    printf 'ERROR: Install Cygwin zip/unzip, or make powershell.exe available.\n' >&2
    exit 1
fi

OUTPUT_ARGUMENT="${1:-dist-zip/JGC-IcedTea-Web-windows-x64.zip}"
if command -v cygpath >/dev/null 2>&1; then
    OUTPUT_ARGUMENT="$(cygpath -u "$OUTPUT_ARGUMENT")"
fi
if [[ "$OUTPUT_ARGUMENT" != /* ]]; then
    OUTPUT_ARGUMENT="$ITW_REPO/$OUTPUT_ARGUMENT"
fi
if [[ "${OUTPUT_ARGUMENT,,}" != *.zip ]]; then
    printf 'ERROR: Output filename must end in .zip.\n' >&2
    exit 1
fi

mkdir -p -- "$(dirname -- "$OUTPUT_ARGUMENT")"
OUTPUT_DIR="$(cd -- "$(dirname -- "$OUTPUT_ARGUMENT")" && pwd -P)"
OUTPUT_ZIP="$OUTPUT_DIR/$(basename -- "$OUTPUT_ARGUMENT")"

# A temporary image inside a source tree would copy itself recursively.
DIST_REAL="$(cd -- "$ITW_DIST" && pwd -P)"
CUSTOMER_REAL="$(cd -- "$ITW_CUSTOMER" && pwd -P)"
case "$OUTPUT_DIR/" in
    "$DIST_REAL/"*|"$CUSTOMER_REAL/"*)
        printf 'ERROR: Place the output ZIP outside dist-native and customer/NR.\n' >&2
        exit 1
        ;;
esac
if [[ -d "$OUTPUT_ZIP" ]]; then
    printf 'ERROR: Output path is a directory: %s\n' "$OUTPUT_ZIP" >&2
    exit 1
fi

# Each run gets a fresh image and archive. Existing ZIPs are replaced only
# after successful packaging; stale entries cannot survive from earlier runs.
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.itw-zip.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
ITW_ZIP_STAGE="$WORK_DIR/image"
TEMP_ZIP="$WORK_DIR/package.zip"
mkdir -p -- "$ITW_ZIP_STAGE"

echo 'Staging the existing Windows distribution...'
cp -a "$ITW_DIST/." "$ITW_ZIP_STAGE/"
# Pick up the current compiled Java code even if dist-native's JAR is older.
cp "$ITW_CLASSES_JAR" "$ITW_ZIP_STAGE/share/icedtea-web/javaws.jar"
mkdir -p "$ITW_ZIP_STAGE/customer/NR" "$ITW_ZIP_STAGE/share/pixmaps"
cp -a "$ITW_CUSTOMER/." "$ITW_ZIP_STAGE/customer/NR/"
cp "$ITW_REPO/javaws.ico" "$ITW_ZIP_STAGE/share/pixmaps/javaws.ico"
cp "$ITW_REPO/COPYING" "$ITW_ZIP_STAGE/COPYING"

echo 'Creating ZIP...'
if [[ "$ZIP_BACKEND" == zip ]]; then
    # Archive the image contents directly: bin/, share/, etc. at ZIP root.
    (cd -- "$ITW_ZIP_STAGE" && zip -q -r "$TEMP_ZIP" .)
    unzip -tq "$TEMP_ZIP"
else
    # Pass paths as environment data, never interpolate them into PS code.
    ITW_ZIP_SOURCE_WIN="$(cygpath -aw "$ITW_ZIP_STAGE")" \
    ITW_ZIP_OUTPUT_WIN="$(cygpath -aw "$TEMP_ZIP")" \
    powershell.exe -NoLogo -NoProfile -NonInteractive -Command '
        $ErrorActionPreference = "Stop"
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory(
                $env:ITW_ZIP_SOURCE_WIN,
                $env:ITW_ZIP_OUTPUT_WIN,
                [System.IO.Compression.CompressionLevel]::Optimal,
                $false
            )
            $archive = [System.IO.Compression.ZipFile]::OpenRead($env:ITW_ZIP_OUTPUT_WIN)
            try {
                foreach ($entry in $archive.Entries) {
                    $stream = $entry.Open()
                    try { $stream.CopyTo([System.IO.Stream]::Null) }
                    finally { $stream.Dispose() }
                }
            } finally { $archive.Dispose() }
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            exit 1
        }
    '
fi

[[ -s "$TEMP_ZIP" ]]
mv -f -- "$TEMP_ZIP" "$OUTPUT_ZIP"
printf '\nZIP generated successfully: %s\n' "$OUTPUT_ZIP"

