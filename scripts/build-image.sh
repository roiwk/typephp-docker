#!/usr/bin/env bash
# Build the image from versions.env.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"
# shellcheck disable=SC1091
set -a
source "${root}/versions.env"
set +a

case "$(uname -m)" in
    x86_64)
        tpc_sha="${TPC_SHA256_X64}"
        sdk_sha="${PHPX_SDK_SHA256_X64}"
        ;;
    aarch64|arm64)
        tpc_sha="${TPC_SHA256_ARM64}"
        sdk_sha="${PHPX_SDK_SHA256_ARM64}"
        ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

ver="${TYPEPHP_VERSION#v}"
php_minor="${PHP_VERSION%.*}"
tags=(-t "typephp:${ver}" -t "typephp:${php_minor}")
if [[ -n "${IMAGE:-}" ]]; then
    image="$(printf '%s' "${IMAGE}" | tr '[:upper:]' '[:lower:]')"
    tags+=(-t "${image}:${ver}" -t "${image}:${php_minor}" -t "${image}:${ver}-php${PHP_VERSION}")
fi

docker build \
    --build-arg "PHP_VERSION=${PHP_VERSION}" \
    --build-arg "PHP_SHA256=${PHP_SHA256}" \
    --build-arg "TYPEPHP_VERSION=${TYPEPHP_VERSION}" \
    --build-arg "PHPX_REF=${PHPX_REF}" \
    --build-arg "PHPY_REF=${PHPY_REF}" \
    --build-arg "MAKE_JOBS=${MAKE_JOBS:-2}" \
    --build-arg "TPC_SHA256=${tpc_sha}" \
    --build-arg "PHPX_SDK_VERSION=${PHPX_SDK_VERSION}" \
    --build-arg "PHPX_SDK_PHP=${PHPX_SDK_PHP}" \
    --build-arg "PHPX_SDK_SHA256=${sdk_sha}" \
    "${tags[@]}" \
    .

if [[ "${PUSH:-}" == 1 ]]; then
    if [[ -z "${IMAGE:-}" ]]; then
        echo "PUSH=1 requires IMAGE, for example ghcr.io/<owner>/typephp" >&2
        exit 1
    fi
    docker push "${image}:${ver}"
    docker push "${image}:${php_minor}"
    docker push "${image}:${ver}-php${PHP_VERSION}"
fi
