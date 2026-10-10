#!/usr/bin/env bash
# Tag suffixes for one build of versions.env.
# Unique: 0.9.4-<12 hex chars of this commit>. A new tag on every publish.
# Fixed:  0.9.4, 0.9.4-php8.4.26. Pushed again so they point at this build.
# Moving: 0.9 (this TypePHP minor), php8.4 (this PHP minor), latest
# A later release on PHP 8.5 tags php8.5 and does not move php8.4.
_typephp_image_tags_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

typephp_image_rev() {
    local rev="${TYPEPHP_IMAGE_REV:-${GITHUB_SHA:-}}"
    if [[ -z "${rev}" ]]; then
        rev="$(git -C "${_typephp_image_tags_root}" rev-parse HEAD 2>/dev/null || true)"
    fi
    if [[ "${rev}" =~ ^[0-9a-fA-F]{12,}$ ]]; then
        printf '%s' "${rev:0:12}"
        return
    fi
    if [[ "${rev}" =~ ^[A-Za-z0-9_.-]{1,40}$ ]]; then
        printf '%s' "${rev}"
    fi
}

typephp_tag_suffixes() {
    local ver="${TYPEPHP_VERSION#v}"
    local rev item seen=""
    rev="$(typephp_image_rev)"
    local items=()
    if [[ -n "${rev}" ]]; then
        items+=("${ver}-${rev}")
    fi
    items+=(
        "${ver}"
        "${ver}-php${PHP_VERSION}"
        "${ver%.*}"
        "php${PHP_VERSION%.*}"
        latest
    )
    for item in "${items[@]}"; do
        case " ${seen} " in
            *" ${item} "*) ;;
            *)
                printf '%s\n' "${item}"
                seen="${seen} ${item}"
                ;;
        esac
    done
}
