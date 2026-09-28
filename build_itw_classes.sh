#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "\nERROR: Java build failed at line %s.\n" "$LINENO" >&2' ERR
trap 'popd' EXIT

if (( $# > 1 )); then
    printf 'Usage: bash %s [JdkHome]\n' "$0" >&2
    exit 1
fi

JDK_ARGUMENT="${1:-C:/cygwin64/zulu8}"

for tool in cygpath make; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'ERROR: Required command not found: %s\n' "$tool" >&2
        printf 'Run this script in Cygwin.\n' >&2
        exit 1
    fi
done

export ITW_REPO
ITW_REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
pushd . 1>&2 &>/dev/null
cd "$ITW_REPO"

# Use a Cygwin path for shell operations.
ITW_JDK_UNIX="$(cygpath -au "$JDK_ARGUMENT")"

if [[ ! -d "$ITW_JDK_UNIX" ]]; then
    printf 'ERROR: JDK directory does not exist: %s\n' "$JDK_ARGUMENT" >&2
    exit 1
fi

# Use Windows-compatible paths for Java and configure.
export ITW_JDK
ITW_JDK="$(cygpath -am "$ITW_JDK_UNIX")"

export JAVA_HOME="$ITW_JDK"
export JAVA="$ITW_JDK/bin/java.exe"
export JRE="$ITW_JDK/jre"
export ITW_BUILD="$ITW_REPO/build-native"
export ITW_DIST="$ITW_REPO/dist-native"
export PATH="$ITW_JDK_UNIX/bin:$PATH"

# The legacy Autotools build contains unquoted path expansions.
if [[ "$ITW_JDK" == *" "* || "$ITW_REPO" == *" "* ]]; then
    printf 'ERROR: This legacy Java build requires JDK and repository paths without spaces.\n' >&2
    exit 1
fi

required_files=(
    "$ITW_JDK_UNIX/bin/java.exe"
    "$ITW_JDK_UNIX/bin/javac.exe"
    "$ITW_JDK_UNIX/bin/jar.exe"
    "$ITW_JDK_UNIX/jre/lib/rt.jar"
    "$ITW_REPO/build-deps/tagsoup.jar"
    "$ITW_REPO/build-deps/js.jar"
    "$ITW_REPO/build-deps/mslinks.jar"
)

for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        printf 'ERROR: Required file is missing: %s\n' "$file" >&2
        exit 1
    fi
done

printf '\nRepository: %s\n' "$ITW_REPO"
printf 'JDK:        %s\n' "$ITW_JDK"

"$ITW_JDK_UNIX/bin/java.exe" -version

if [[ ! -f configure ]]; then
    printf '\nGenerating configure...\n'
    bash ./autogen.sh
fi

# Reconfigure every time so the selected JDK is actually used.
printf '\nConfiguring the Java build...\n'

bash ./configure \
    --with-jdk-home="$ITW_JDK" \
    --with-itw-libs=BUNDLED \
    --with-tagsoup="$ITW_REPO/build-deps/tagsoup.jar" \
    --with-mslinks="$ITW_REPO/build-deps/mslinks.jar" \
    --with-rhino="$ITW_REPO/build-deps/js.jar" \
    --disable-native-plugin \
    --disable-docs \
    --enable-shell-launchers

# The first make target is always clean.
printf '\nCleaning build outputs...\n'

# Skip integration-test certificate cleanup.
# A normal Java build does not create that test keystore.
make --assume-old=netx-dist-tests-remove-cert-from-public clean

printf '\nBuilding Java classes and JAR...\n'
make stamps/netx-dist.stamp

ITW_CLASSES_JAR="$ITW_REPO/netx.build/lib/classes.jar"

if [[ ! -s "$ITW_CLASSES_JAR" ]]; then
    printf 'ERROR: Expected JAR was not generated: %s\n' "$ITW_CLASSES_JAR" >&2
    exit 1
fi

printf '\nJava build completed successfully.\n'
printf 'JAR: %s\n' "$ITW_CLASSES_JAR"

exit 0
