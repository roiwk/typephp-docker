#!/usr/bin/env bash
# Tag the already built local image and push it. Does not compile PHP again.
# Usage: scripts/publish-image.sh [ghcr.io/roiwk/typephp-docker]
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
    echo "example: scripts/publish-image.sh ghcr.io/roiwk/typephp-docker" >&2
    exit 1
fi
image="$(printf '%s' "${image}" | tr '[:upper:]' '[:lower:]')"

# shellcheck source=image-tags.sh
source "${root}/scripts/image-tags.sh"
ver="${TYPEPHP_VERSION#v}"
source_image=""
for candidate in "typephp:${ver}" typephp:latest "typephp:${PHP_VERSION%.*}"; do
    if docker image inspect "${candidate}" >/dev/null 2>&1; then
        source_image="${candidate}"
        break
    fi
done
if [[ -z "${source_image}" ]]; then
    echo "local image typephp:${ver} is missing; build it once with scripts/build-image.sh" >&2
    exit 1
fi

while IFS= read -r suffix; do
    docker tag "${source_image}" "${image}:${suffix}"
    docker push "${image}:${suffix}"
done < <(typephp_tag_suffixes)

echo "pushed ${image}:${ver}"
