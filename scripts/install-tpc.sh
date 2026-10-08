#!/usr/bin/env bash
# Install the self-hosted tpc binary published for this PHP version.
# The archive contains only tpc; libphp.so and libphpx.so come from this image.
set -euo pipefail

: "${TYPEPHP_VERSION:?TYPEPHP_VERSION is required}"
: "${PHP_VERSION:?PHP_VERSION is required}"

case "$(uname -m)" in
    x86_64) platform="x64" ;;
    aarch64|arm64) platform="arm64" ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

asset="tpc_${TYPEPHP_VERSION}_linux_${platform}_php${PHP_VERSION}-zts.tar.gz"
if [[ -n "${TPC_SHA256:-}" ]]; then
    expected="${TPC_SHA256}"
else
    case "${asset}" in
        tpc_v0.9.4_linux_x64_php8.4.26-zts.tar.gz)
            expected="2fd0dc85f1b89b00b6003fa25755b19e3535802f9046e55fb4fca742ad080c8f"
            ;;
        tpc_v0.9.4_linux_arm64_php8.4.26-zts.tar.gz)
            expected="b4efc60e274eb277f30ef05ac1cacfb38b20c0272cf24c6d1d00d650eceb3423"
            ;;
        *)
            echo "no checksum for ${asset}; set TPC_SHA256 from versions.env" >&2
            exit 1
            ;;
    esac
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

attempt=0
until curl -fL --retry 3 --retry-all-errors --retry-delay 2 \
    -o "${workdir}/tpc.tar.gz" \
    "https://github.com/swoole/typephp/releases/download/${TYPEPHP_VERSION}/${asset}"
do
    attempt=$((attempt + 1))
    if [[ "${attempt}" -ge 8 ]]; then
        echo "failed to download ${asset}" >&2
        exit 1
    fi
    sleep $((attempt * 3))
done
echo "${expected}  ${workdir}/tpc.tar.gz" | sha256sum -c -
tar -xzf "${workdir}/tpc.tar.gz" -C "${workdir}"

tpc_bin="$(find "${workdir}" -type f -name tpc -print -quit)"
test -n "${tpc_bin}"
install -m 0755 "${tpc_bin}" /usr/local/bin/tpc

# The release binary records the GitHub Actions library path. Point it at
# the copies built in this image so it runs without LD_LIBRARY_PATH.
patchelf --set-rpath "${PHPX_HOME}/lib:${PHP_HOME}/lib" /usr/local/bin/tpc
ldconfig
