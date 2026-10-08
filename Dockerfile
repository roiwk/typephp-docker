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

COPY scripts/tpc-static.sh scripts/tpc-private.sh scripts/entrypoint.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && install -m 0755 /tmp/scripts/tpc-static.sh /usr/local/bin/tpc-static \
    && install -m 0755 /tmp/scripts/tpc-private.sh /usr/local/bin/tpc-private \
    && install -m 0755 /tmp/scripts/entrypoint.sh /usr/local/bin/typephp-entrypoint \
    && rm -rf /tmp/scripts

WORKDIR /src
ENV TYPEPHP_LINK=shared
ENTRYPOINT ["/usr/local/bin/typephp-entrypoint"]
CMD ["tpc", "--version"]
