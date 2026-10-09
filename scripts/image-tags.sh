#!/usr/bin/env bash
# Tag suffixes for one build of versions.env.
# Fixed:  0.9.4, 0.9.4-php8.4.26
# Moving: 0.9 (this TypePHP minor), php8.4 (this PHP minor), latest
# A later release on PHP 8.5 tags php8.5 and does not move php8.4.
typephp_tag_suffixes() {
    local ver="${TYPEPHP_VERSION#v}"
    local item seen=""
    local items=(
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
