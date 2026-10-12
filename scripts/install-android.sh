#!/usr/bin/env bash
# Android arm64-v8a cross tools for tpc --target-platform aarch64-linux-android24.
# tpc reads the PHPX SDK at $PHPX_HOME/android/arm64-v8a and the NDK clang++ at
# $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++.
# iOS and macOS apps need Xcode on a Mac; tpc refuses an iOS target on Linux.
set -euo pipefail

: "${PHPX_HOME:?PHPX_HOME is required}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-r27d}"
ANDROID_NDK_SHA256="${ANDROID_NDK_SHA256:-}"
ANDROID_CMDLINE_TOOLS_SHA256="${ANDROID_CMDLINE_TOOLS_SHA256:-7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee}"
PHPX_ANDROID_SDK_SHA256="${PHPX_ANDROID_SDK_SHA256:-c7d142c151fd14fd8f652487f1404deffe94c08a9ab9cbb3e2bfd47f81b79f88}"

download() {
    local url="$1" dest="$2" expected="$3"
    local host_cache="${ANDROID_HOST_CACHE:-}"
    if [[ -n "${host_cache}" && -s "${host_cache}/$(basename "${dest}")" ]]; then
        cp -f "${host_cache}/$(basename "${dest}")" "${dest}"
    fi
    local cache_root="${ANDROID_DOWNLOAD_CACHE:-}"
    local cached=""
    if [[ ! -s "${dest}" && -n "${cache_root}" ]]; then
        mkdir -p "${cache_root}"
        cached="${cache_root}/$(printf '%s' "${url}" | sha256sum | awk '{print $1}')"
        if [[ -s "${cached}" ]]; then
            cp -f "${cached}" "${dest}"
        fi
    fi
    if [[ ! -s "${dest}" ]]; then
        local attempt=0
        until curl -4 -fL --connect-timeout 20 --retry 3 --retry-all-errors --retry-delay 2 \
            --speed-limit 20000 --speed-time 30 -o "${dest}" "${url}"; do
            attempt=$((attempt + 1))
            rm -f "${dest}"
            if [[ "${attempt}" -ge 8 ]]; then
                echo "failed to download ${url}" >&2
                exit 1
            fi
            sleep $((attempt * 3))
        done
        if [[ -n "${cached}" ]]; then
            cp -f "${dest}" "${cached}"
        fi
    fi
    if [[ -n "${expected}" ]] && ! echo "${expected}  ${dest}" | sha256sum -c -; then
        rm -f "${dest}" "${cached}"
        exit 1
    fi
}

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

download \
    "https://github.com/swoole/phpx/releases/download/v2.9.3/phpx-sdk_v2.9.3_php8.4.25_android-arm64-v8a.tar.xz" \
    "${workdir}/phpx-android.tar.xz" \
    "${PHPX_ANDROID_SDK_SHA256}"
rm -rf "${PHPX_HOME}/android/arm64-v8a"
mkdir -p "${PHPX_HOME}/android/arm64-v8a"
tar -xJf "${workdir}/phpx-android.tar.xz" -C "${PHPX_HOME}/android/arm64-v8a" --strip-components=1
abi_stamp="${PHPX_HOME}/android/arm64-v8a/.typephp-android-sdk-abi"
test -s "${PHPX_HOME}/android/arm64-v8a/lib/libphp.a"
test -s "${PHPX_HOME}/android/arm64-v8a/lib/libphpx.a"
test "$(tr -d '[:space:]' < "${abi_stamp}")" = "typephp-android-arm64-v8a-api24-phpx-sdk-abi-v1"
rm -f "${workdir}/phpx-android.tar.xz"

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "Android NDK ${ANDROID_NDK_VERSION} publishes a Linux x86_64 host toolchain only; skipping it on $(uname -m)." >&2
    exit 0
fi

if [[ -z "${ANDROID_NDK_SHA256}" ]]; then
    case "${ANDROID_NDK_VERSION}" in
        r27d) ANDROID_NDK_SHA256="601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9" ;;
        *)
            echo "no checksum for Android NDK ${ANDROID_NDK_VERSION}; set ANDROID_NDK_SHA256" >&2
            exit 1
            ;;
    esac
fi

download \
    "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
    "${workdir}/ndk.zip" \
    "${ANDROID_NDK_SHA256}"
rm -rf "/opt/android-ndk-${ANDROID_NDK_VERSION}"
unzip -q "${workdir}/ndk.zip" -d /opt
test -x "/opt/android-ndk-${ANDROID_NDK_VERSION}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
ln -sfn "/opt/android-ndk-${ANDROID_NDK_VERSION}" /opt/android-ndk
rm -f "${workdir}/ndk.zip"

download \
    "https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip" \
    "${workdir}/cmdline-tools.zip" \
    "${ANDROID_CMDLINE_TOOLS_SHA256}"
rm -rf /opt/android-sdk/cmdline-tools
mkdir -p /opt/android-sdk/cmdline-tools
unzip -q "${workdir}/cmdline-tools.zip" -d "${workdir}/cmdline"
test -x "${workdir}/cmdline/cmdline-tools/bin/sdkmanager"
mv "${workdir}/cmdline/cmdline-tools" /opt/android-sdk/cmdline-tools/latest
rm -f "${workdir}/cmdline-tools.zip"

export ANDROID_SDK_ROOT=/opt/android-sdk
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.net.preferIPv4Stack=true"
mkdir -p "${ANDROID_SDK_ROOT}/licenses" "${HOME}/.android"
touch "${HOME}/.android/repositories.cfg"
printf '%s\n' '24333f8a63b6825ea9c5514f83c2829b004d1fee' > "${ANDROID_SDK_ROOT}/licenses/android-sdk-license"
"${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --sdk_root="${ANDROID_SDK_ROOT}" --install \
    "platforms;android-36" \
    "build-tools;36.0.0" \
    "platform-tools"
test -f "${ANDROID_SDK_ROOT}/platforms/android-36/android.jar"
test -x "${ANDROID_SDK_ROOT}/build-tools/36.0.0/aapt2"
test -x "${ANDROID_SDK_ROOT}/build-tools/36.0.0/d8"
test -x "${ANDROID_SDK_ROOT}/build-tools/36.0.0/apksigner"
test -x "${ANDROID_SDK_ROOT}/platform-tools/adb"
ln -sfn "${ANDROID_SDK_ROOT}/build-tools/36.0.0" "${ANDROID_SDK_ROOT}/build-tools/latest"
rm -rf "${HOME}/.android/cache" "${ANDROID_SDK_ROOT}/.temp"
