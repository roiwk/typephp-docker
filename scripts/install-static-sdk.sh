#!/usr/bin/env bash
# Install the prebuilt PHPX full-static SDK where tpc --full-static looks:
# $PHPX_HOME/full-static/sdk
set -euo pipefail

: "${PHPX_HOME:?PHPX_HOME is required}"
: "${PHPX_SDK_VERSION:?PHPX_SDK_VERSION is required}"
: "${PHPX_SDK_PHP:?PHPX_SDK_PHP is required}"
: "${PHPX_SDK_SHA256:?PHPX_SDK_SHA256 is required}"

case "$(uname -m)" in
    x86_64) target="linux-x64" ;;
    aarch64|arm64) target="linux-arm64" ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

asset="phpx-sdk_${PHPX_SDK_VERSION}_php${PHPX_SDK_PHP}_${target}.tar.xz"
url="https://github.com/swoole/phpx/releases/download/${PHPX_SDK_VERSION}/${asset}"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

attempt=0
until curl -fL --retry 3 --retry-all-errors --retry-delay 2 \
    -o "${workdir}/sdk.tar.xz" "${url}"
do
    attempt=$((attempt + 1))
    if [[ "${attempt}" -ge 8 ]]; then
        echo "failed to download ${asset}" >&2
        exit 1
    fi
    sleep $((attempt * 3))
done
echo "${PHPX_SDK_SHA256}  ${workdir}/sdk.tar.xz" | sha256sum -c -

mkdir -p "${workdir}/extract"
tar -xJf "${workdir}/sdk.tar.xz" -C "${workdir}/extract"
inner="$(find "${workdir}/extract" -mindepth 1 -maxdepth 1 -type d -print -quit)"
test -n "${inner}"

dest="${PHPX_HOME}/full-static/sdk"
rm -rf "${dest}"
mkdir -p "${dest}"
cp -a "${inner}/." "${dest}/"

test -s "${dest}/lib/libphp.a"
test -s "${dest}/lib/libphpx.a"
if ! find "${dest}" -name crt1.o -print -quit | grep -q .; then
    echo "SDK ${asset} has no musl crt1.o; tpc --full-static cannot link" >&2
    exit 1
fi

echo "Installed full-static SDK at ${dest}"
