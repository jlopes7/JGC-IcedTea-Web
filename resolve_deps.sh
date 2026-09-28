#!/usr/bin/env bash

set -E pipefail

BASEDIR=$(dirname $(readlink -f $0))

trap 'popd &>/dev/null' EXIT

mkdir -p $BASEDIR/build-deps

pushd . &>/dev/null

curl -fL \
  "https://repo.maven.apache.org/maven2/org/ccil/cowan/tagsoup/tagsoup/1.2.1/tagsoup-1.2.1.jar" \
  -o build-deps/tagsoup.jar

curl -fL \
  "https://repo.maven.apache.org/maven2/com/github/vatbub/mslinks/1.0.5/mslinks-1.0.5.jar" \
  -o build-deps/mslinks.jar

curl -fL \
  "https://ftp.mozilla.org/pub/js/rhino1_6R7.zip" \
  -o build-deps/rhino.zip

command -v unzip &>/dev/null && unzip -j -o build-deps/rhino.zip "*/js.jar" -d build-deps || {
	echo "[ERR] Cannot resolve the command 'unzip'. Please install it before continuing"
	rm -rf build-deps/

	exit 1
}

exit 0

