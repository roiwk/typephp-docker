#!/usr/bin/env bash
# Tag the already built local image and push it. Does not compile PHP again.
# Usage: scripts/publish-image.sh [ghcr.io/<owner>/typephp]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preset_image="${IMAGE-}"
# shellcheck disable=SC1091
set -a
source "${root}/versions.env"
set +a
if [[ -n "${preset_image}" ]]; then
    IMAGE="${preset_image}"
fi

image="${1:-${IMAGE:-}}"
if [[ -z "${image}" ]]; then
    echo "pass the image name, or set IMAGE in versions.env" >&2
    echo "example: scripts/publish-image.sh ghcr.io/<owner>/typephp" >&2
    exit 1
fi
image="$(printf '%s' "${image}" | tr '[:upper:]' '[:lower:]')"

if ! docker image inspect typephp:8.4 >/dev/null 2>&1; then
    echo "local image typephp:8.4 is missing; build it once with scripts/build-image.sh" >&2
    exit 1
fi

ver="${TYPEPHP_VERSION#v}"
php_minor="${PHP_VERSION%.*}"
for tag in "${php_minor}" "${ver}" "${ver}-php${PHP_VERSION}"; do
    docker tag typephp:8.4 "${image}:${tag}"
    docker push "${image}:${tag}"
done

echo "pushed ${image}:${php_minor}"
