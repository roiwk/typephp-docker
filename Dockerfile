# TypePHP compiler image.
# Matches the Linux release of https://github.com/swoole/typephp (v0.9.4):
# PHP 8.4.26 ZTS with Embed SAPI, and the PHPX revision used to build tpc.

FROM ubuntu:24.04

ARG PHP_VERSION=8.4.26
ARG PHP_SHA256=32a2de53862ad44ed4a5005244ce4f1b50c271e74dced215449a4443b40569f1
ARG TYPEPHP_VERSION=v0.9.4
ARG PHPX_REF=a0138bbdd6cbfda62225adc56c558d0742114c8a
ARG PHPY_REF=5b9c650316ad87644e885a64a0a6767b03abdfa6
ARG MAKE_JOBS=2

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VERSION=${PHP_VERSION} \
    PHP_SHA256=${PHP_SHA256} \
    TYPEPHP_VERSION=${TYPEPHP_VERSION} \
    PHPX_REF=${PHPX_REF} \
    MAKE_JOBS=${MAKE_JOBS} \
    PHP_HOME=/opt/php \
    PHPX_HOME=/opt/phpx \
    PATH=/opt/php/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_LIBRARY_PATH=/opt/php/lib:/opt/phpx/lib \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        bison \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libargon2-dev \
        libcurl4-openssl-dev \
        libffi-dev \
        libgmp-dev \
        libmpfr-dev \
        libonig-dev \
        libreadline-dev \
        libsodium-dev \
        libsqlite3-dev \
        libssl-dev \
        libxml2-dev \
        libzip-dev \
        ninja-build \
        pkg-config \
        patchelf \
        re2c \
        unzip \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' "${PHP_HOME}/lib" "${PHPX_HOME}/lib" > /etc/ld.so.conf.d/typephp.conf

COPY scripts/build-php.sh /tmp/scripts/build-php.sh
RUN chmod +x /tmp/scripts/build-php.sh && /tmp/scripts/build-php.sh

COPY scripts/build-phpx.sh /tmp/scripts/build-phpx.sh
RUN chmod +x /tmp/scripts/build-phpx.sh && /tmp/scripts/build-phpx.sh

COPY scripts/build-phpy.sh /tmp/scripts/build-phpy.sh
RUN chmod +x /tmp/scripts/build-phpy.sh \
    && PHPY_REF="${PHPY_REF}" /tmp/scripts/build-phpy.sh

ARG TPC_SHA256=
ARG PHPX_SDK_VERSION=v2.9.3
ARG PHPX_SDK_PHP=8.4.25
ARG PHPX_SDK_SHA256=9fb69fe3e941edbae497d09bbcb09708b717320a7d5d81871ef28b56839f0285
ARG TYPEPHP_SOURCE_SHA256=e085e197ce6505a15b310291f3f1347dfac11f60b977cfd7c56861e1879f2502
ARG PHPX_WASI_SDK_VERSION=v2.9.3
ARG PHPX_WASI_SDK_PHP=8.5.9
ARG PHPX_WASI_SDK_SHA256=31526c077fb512896546c85026eef01aa0aced36d651f64513f5235b6648249d
ARG WASI_SDK_VERSION=33.0
ARG WASI_SDK_SHA256=
ARG WASMTIME_VERSION=v49.0.2
ARG WASMTIME_SHA256=

COPY scripts/install-tpc.sh scripts/smoke-test.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/install-tpc.sh /tmp/scripts/smoke-test.sh \
    && attempt=0 \
    && until curl -fL --retry 3 --retry-all-errors --retry-delay 2 \
        -o /usr/local/bin/composer \
        https://github.com/composer/composer/releases/latest/download/composer.phar; do \
        attempt=$((attempt + 1)); \
        if [ "${attempt}" -ge 8 ]; then exit 1; fi; \
        sleep $((attempt * 3)); \
    done \
    && chmod +x /usr/local/bin/composer \
    && composer --version \
    && /tmp/scripts/install-tpc.sh \
    && /tmp/scripts/smoke-test.sh \
    && rm -rf /tmp/scripts /root/.composer /root/.typephp /tmp/typephp-*

COPY scripts/install-static-sdk.sh /tmp/scripts/install-static-sdk.sh
RUN apt-get update \
    && attempt=0 \
    && until apt-get install -y --no-install-recommends clang; do \
        attempt=$((attempt + 1)); \
        if [ "${attempt}" -ge 5 ]; then exit 1; fi; \
        sleep $((attempt * 5)); \
        apt-get update || true; \
    done \
    && rm -rf /var/lib/apt/lists/* \
    && chmod +x /tmp/scripts/install-static-sdk.sh \
    && PHPX_SDK_VERSION="${PHPX_SDK_VERSION}" \
        PHPX_SDK_PHP="${PHPX_SDK_PHP}" \
        PHPX_SDK_SHA256="${PHPX_SDK_SHA256}" \
        /tmp/scripts/install-static-sdk.sh \
    && rm -rf /tmp/scripts

COPY scripts/install-wasm.sh /tmp/scripts/install-wasm.sh
RUN chmod +x /tmp/scripts/install-wasm.sh \
    && TYPEPHP_VERSION="${TYPEPHP_VERSION}" \
        TYPEPHP_SOURCE_SHA256="${TYPEPHP_SOURCE_SHA256}" \
        PHPX_WASI_SDK_VERSION="${PHPX_WASI_SDK_VERSION}" \
        PHPX_WASI_SDK_PHP="${PHPX_WASI_SDK_PHP}" \
        PHPX_WASI_SDK_SHA256="${PHPX_WASI_SDK_SHA256}" \
        WASI_SDK_VERSION="${WASI_SDK_VERSION}" \
        WASI_SDK_SHA256="${WASI_SDK_SHA256}" \
        WASMTIME_VERSION="${WASMTIME_VERSION}" \
        WASMTIME_SHA256="${WASMTIME_SHA256}" \
        /tmp/scripts/install-wasm.sh \
    && rm -rf /tmp/scripts

ARG PHP_NANO_VERSION=v1.1.0
ARG PHP_NANO_SHA256=f9d59c03b0cf6d1121ff3fe699fd00d7357b28df8f2ae9633a0448c7f1d2c064

COPY scripts/install-nano.sh /tmp/scripts/install-nano.sh
RUN chmod +x /tmp/scripts/install-nano.sh \
    && PHP_NANO_VERSION="${PHP_NANO_VERSION}" \
        PHP_NANO_SHA256="${PHP_NANO_SHA256}" \
        /tmp/scripts/install-nano.sh \
    && rm -rf /tmp/scripts

ARG PHPX_ANDROID_SDK_SHA256=c7d142c151fd14fd8f652487f1404deffe94c08a9ab9cbb3e2bfd47f81b79f88
ARG ANDROID_NDK_VERSION=r27d
ARG ANDROID_NDK_SHA256=601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9
ARG ANDROID_CMDLINE_TOOLS_SHA256=7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee

RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-21-jdk-headless zip \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/install-android.sh /tmp/scripts/install-android.sh
RUN --mount=type=cache,target=/var/cache/typephp-android \
    --mount=type=bind,from=androidcache,source=/,target=/tmp/android-host-cache,ro \
    chmod +x /tmp/scripts/install-android.sh \
    && PHPX_ANDROID_SDK_SHA256="${PHPX_ANDROID_SDK_SHA256}" \
        ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION}" \
        ANDROID_NDK_SHA256="${ANDROID_NDK_SHA256}" \
        ANDROID_CMDLINE_TOOLS_SHA256="${ANDROID_CMDLINE_TOOLS_SHA256}" \
        ANDROID_DOWNLOAD_CACHE=/var/cache/typephp-android \
        ANDROID_HOST_CACHE=/tmp/android-host-cache \
        /tmp/scripts/install-android.sh \
    && rm -rf /tmp/scripts

COPY scripts/tpc-static.sh scripts/tpc-private.sh scripts/entrypoint.sh scripts/enable-extensions.sh scripts/extension-mode.sh scripts/chown-output.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && install -m 0755 /tmp/scripts/tpc-static.sh /usr/local/bin/tpc-static \
    && install -m 0755 /tmp/scripts/tpc-private.sh /usr/local/bin/tpc-private \
    && install -m 0755 /tmp/scripts/entrypoint.sh /usr/local/bin/typephp-entrypoint \
    && install -m 0755 /tmp/scripts/enable-extensions.sh /usr/local/bin/typephp-ext \
    && install -m 0755 /tmp/scripts/chown-output.sh /usr/local/bin/typephp-chown-output \
    && install -m 0644 /tmp/scripts/extension-mode.sh /usr/local/bin/typephp-ext-mode.sh \
    && rm -rf /tmp/scripts

WORKDIR /src
ENV TYPEPHP_LINK=shared \
    TYPEPHP_ZTS=off \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-ndk \
    PHPX_ANDROID_SDK_DIR=/opt/phpx/android/arm64-v8a \
    PATH="/opt/android-sdk/platform-tools:/opt/android-sdk/build-tools/latest:/opt/android-sdk/cmdline-tools/latest/bin:/opt/wasi-sdk/bin:/opt/php/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENTRYPOINT ["/usr/local/bin/typephp-entrypoint"]
CMD ["tpc", "--version"]
