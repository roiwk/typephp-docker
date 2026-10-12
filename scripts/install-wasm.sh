#!/usr/bin/env bash
# Install what `tpc --wasm` looks up next to itself and under PHPX_HOME.
# tpc refuses --php-builder/--full-static in this mode. It runs
# /usr/local/bin/wasm/build-program.sh, which needs wasm32-wasip2-clang++
# on PATH and the prebuilt SDK at $PHPX_HOME/wasm/wasm32-wasip2.
set -euo pipefail

: "${TYPEPHP_VERSION:?TYPEPHP_VERSION is required}"
: "${PHPX_HOME:?PHPX_HOME is required}"
PHPX_WASI_SDK_VERSION="${PHPX_WASI_SDK_VERSION:-v2.9.3}"
PHPX_WASI_SDK_PHP="${PHPX_WASI_SDK_PHP:-8.5.9}"

download() {
    local url="$1" dest="$2" expected="$3"
    local attempt=0
    until curl -fL --retry 3 --retry-all-errors --retry-delay 2 -o "${dest}" "${url}"; do
        attempt=$((attempt + 1))
        if [[ "${attempt}" -ge 8 ]]; then
            echo "failed to download ${url}" >&2
            exit 1
        fi
        sleep $((attempt * 3))
    done
    echo "${expected}  ${dest}" | sha256sum -c -
}

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

source_sha="${TYPEPHP_SOURCE_SHA256:-}"
if [[ -z "${source_sha}" ]]; then
    case "${TYPEPHP_VERSION}" in
        v0.9.4) source_sha="e085e197ce6505a15b310291f3f1347dfac11f60b977cfd7c56861e1879f2502" ;;
        *)
            echo "no TypePHP source checksum for ${TYPEPHP_VERSION}; set TYPEPHP_SOURCE_SHA256" >&2
            exit 1
            ;;
    esac
fi
download \
    "https://github.com/swoole/typephp/archive/refs/tags/${TYPEPHP_VERSION}.tar.gz" \
    "${workdir}/typephp.tar.gz" \
    "${source_sha}"
mkdir -p "${workdir}/typephp"
tar -xzf "${workdir}/typephp.tar.gz" -C "${workdir}/typephp"
wasm_src="$(find "${workdir}/typephp" -type f -path '*/wasm/build-program.sh' -print -quit)"
test -n "${wasm_src}"
install -d -m 0755 /usr/local/bin/wasm
install -m 0755 \
    "${wasm_src}" \
    "$(dirname "${wasm_src}")/build-nano-program.sh" \
    "$(dirname "${wasm_src}")/build-sdk.sh" \
    /usr/local/bin/wasm/
# libphpx.a from the WASI package stops at core/std. tpc still calls the
# TypePHP runtime, call-cache, and attribute objects, so compile them per program.
if ! grep -q '/src/misc/typephp_runtime.cc' /usr/local/bin/wasm/build-program.sh; then
    builder_tmp="$(mktemp)"
    inserted=
    while IFS= read -r row || [[ -n "${row}" ]]; do
        printf '%s\n' "${row}"
        if [[ "${row}" == 'generated_sources+=("${typephp_runtime_source}")' && -z "${inserted}" ]]; then
            cat << 'EOF'
# The prebuilt WASI libphpx.a does not include these TypePHP objects.
for extra in \
    "${phpx_dir}/src/misc/typephp_runtime.cc" \
    "${phpx_dir}/src/typephp/typephp_attribute.cc" \
    "${phpx_dir}/src/typephp/typephp_call.cc" \
    "${phpx_dir}/src/typephp/typephp_property.cc" \
    "${phpx_dir}/src/typephp/typephp_trait.cc"
do
    if [[ -f "${extra}" ]]; then
        generated_sources+=("${extra}")
    fi
done
EOF
            inserted=1
        fi
    done < /usr/local/bin/wasm/build-program.sh > "${builder_tmp}"
    test -n "${inserted}"
    mv "${builder_tmp}" /usr/local/bin/wasm/build-program.sh
    chmod 0755 /usr/local/bin/wasm/build-program.sh
fi

wasi_php_sha="${PHPX_WASI_SDK_SHA256:-}"
if [[ -z "${wasi_php_sha}" ]]; then
    case "${PHPX_WASI_SDK_VERSION}_${PHPX_WASI_SDK_PHP}" in
        v2.9.3_8.5.9) wasi_php_sha="31526c077fb512896546c85026eef01aa0aced36d651f64513f5235b6648249d" ;;
        *)
            echo "no PHPX WASI SDK checksum for ${PHPX_WASI_SDK_VERSION} php ${PHPX_WASI_SDK_PHP}" >&2
            exit 1
            ;;
    esac
fi
wasi_php_asset="phpx-wasi-sdk_${PHPX_WASI_SDK_VERSION}_php${PHPX_WASI_SDK_PHP}_wasm32-wasip2.tar.gz"
download \
    "https://github.com/swoole/phpx/releases/download/${PHPX_WASI_SDK_VERSION}/${wasi_php_asset}" \
    "${workdir}/phpx-wasi.tar.gz" \
    "${wasi_php_sha}"
mkdir -p "${workdir}/phpx-wasi"
tar -xzf "${workdir}/phpx-wasi.tar.gz" -C "${workdir}/phpx-wasi"
wasi_php_inner="$(find "${workdir}/phpx-wasi" -mindepth 1 -maxdepth 1 -type d -print -quit)"
test -n "${wasi_php_inner}"
wasi_php_dest="${PHPX_HOME}/wasm/wasm32-wasip2"
rm -rf "${wasi_php_dest}"
mkdir -p "${wasi_php_dest}"
cp -a "${wasi_php_inner}/." "${wasi_php_dest}/"
test -s "${wasi_php_dest}/lib/libphp.a"
test -s "${wasi_php_dest}/lib/libphpx.a"
grep -qx 'typephp-wasip2-sdk-abi-v4' "${wasi_php_dest}/.typephp-wasi-sdk-abi"
# v2.9.3 phpx.h includes these two policy headers, but the WASI tarball
# leaves them out. They are macros and match the PHPX built into this image.
for header in phpx_exception_policy.h phpx_cast_policy.h typephp_opcode_table.h; do
    if [[ ! -s "${wasi_php_dest}/include/phpx/${header}" ]]; then
        cp "${PHPX_HOME}/include/${header}" "${wasi_php_dest}/include/phpx/${header}"
    fi
    test -s "${wasi_php_dest}/include/phpx/${header}"
done
# WASI SDK 33's libc++ does not expose these through the headers phpx.h
# already includes. std::fill/std::copy need <algorithm>, std::abort needs <cstdlib>.
phpx_header="${wasi_php_dest}/include/phpx/phpx.h"
if ! grep -q '#include <algorithm>' "${phpx_header}"; then
    sed -i 's|#include <utility>|#include <utility>\n#include <algorithm>\n#include <cstdlib>|' "${phpx_header}"
fi
grep -q '#include <algorithm>' "${phpx_header}"
grep -q '#include <cstdlib>' "${phpx_header}"

wasi_sdk_version="${WASI_SDK_VERSION:-33.0}"
case "$(uname -m)" in
    x86_64)
        wasi_sdk_asset="wasi-sdk-${wasi_sdk_version}-x86_64-linux.tar.gz"
        wasi_sdk_sha="${WASI_SDK_SHA256:-0ba8b5bfaeb2adf3f29bab5841d76cf5318ab8e1642ea195f88baba1abd47bce}"
        ;;
    aarch64|arm64)
        wasi_sdk_asset="wasi-sdk-${wasi_sdk_version}-arm64-linux.tar.gz"
        wasi_sdk_sha="${WASI_SDK_SHA256:-4f98ee738c7abb45c81a94d1461fc53cc569d1cd01498951c8184d841a027844}"
        ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac
if [[ -z "${wasi_sdk_sha}" ]]; then
    echo "no WASI SDK checksum for ${wasi_sdk_asset}; set WASI_SDK_SHA256" >&2
    exit 1
fi
download \
    "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${wasi_sdk_version%%.*}/${wasi_sdk_asset}" \
    "${workdir}/wasi-sdk.tar.gz" \
    "${wasi_sdk_sha}"
mkdir -p "${workdir}/wasi-sdk"
tar -xzf "${workdir}/wasi-sdk.tar.gz" -C "${workdir}/wasi-sdk"
wasi_sdk_inner="$(find "${workdir}/wasi-sdk" -mindepth 1 -maxdepth 1 -type d -print -quit)"
test -n "${wasi_sdk_inner}"
rm -rf /opt/wasi-sdk
mkdir -p /opt/wasi-sdk
cp -a "${wasi_sdk_inner}/." /opt/wasi-sdk/
test -x /opt/wasi-sdk/bin/wasm32-wasip2-clang++

wasmtime_version="${WASMTIME_VERSION:-v49.0.2}"
case "$(uname -m)" in
    x86_64)
        wasmtime_asset="wasmtime-${wasmtime_version}-x86_64-linux.tar.xz"
        wasmtime_sha="${WASMTIME_SHA256:-a4d6e9e3a5a60f527cf7793d674c48930c80c2e8977995b8a275cad3254b9322}"
        ;;
    aarch64|arm64)
        wasmtime_asset="wasmtime-${wasmtime_version}-aarch64-linux.tar.xz"
        wasmtime_sha="${WASMTIME_SHA256:-ca14988c6da3d92512bd9c3bad6cbd06b1f5743b6911a9e709f1a6fa30637d7f}"
        ;;
esac
download \
    "https://github.com/bytecodealliance/wasmtime/releases/download/${wasmtime_version}/${wasmtime_asset}" \
    "${workdir}/wasmtime.tar.xz" \
    "${wasmtime_sha}"
mkdir -p "${workdir}/wasmtime"
tar -xJf "${workdir}/wasmtime.tar.xz" -C "${workdir}/wasmtime"
wasmtime_bin="$(find "${workdir}/wasmtime" -type f -name wasmtime -print -quit)"
test -n "${wasmtime_bin}"
install -m 0755 "${wasmtime_bin}" /usr/local/bin/wasmtime

echo "Installed TypePHP wasm scripts, PHPX WASI SDK, WASI SDK ${wasi_sdk_version}, and wasmtime ${wasmtime_version}"
