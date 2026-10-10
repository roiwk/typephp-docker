#!/usr/bin/env bash
# Compile with a private static PHP embed (--php-builder).
# The binary does not need the image libphp.so. It still dynamically links
# system libraries such as libstdc++, GMP, and OpenSSL.
# --php-version accepts a minor line (8.4 or 8.5), and its default is 8.5.
# Passing the image line makes tpc download the patch this binary was built
# with, for example 8.4.26, instead of the newest 8.5 release.
set -euo pipefail

# shellcheck source=/usr/local/bin/typephp-ext-mode.sh
source /usr/local/bin/typephp-ext-mode.sh

has_flag() {
    local name="$1"
    shift
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == "${name}" || "${arg}" == "${name}="* ]]; then
            return 0
        fi
    done
    return 1
}

php_version_arg() {
    local prev="" arg
    for arg in "$@"; do
        if [[ "${prev}" == "--php-version" ]]; then
            printf '%s\n' "${arg}"
            return 0
        fi
        if [[ "${arg}" == --php-version=* ]]; then
            printf '%s\n' "${arg#--php-version=}"
            return 0
        fi
        prev="${arg}"
    done
    return 1
}

cmd=(tpc "$@")
if ! has_flag --php-builder "$@"; then
    extension_selection="$(typephp_extension_selection)"
    if [[ "${extension_selection}" == omit || "${extension_selection}" == minimal ]]; then
        ext_yaml="[]"
    else
        ext_yaml="[${extension_selection}]"
    fi
    cmd+=(--php-builder="extensions: ${ext_yaml}; zts: ${TYPEPHP_ZTS:-off}")
fi
# tpc rejects a patch number here. The minor line selects the matching patch.
if [[ -n "${PHP_VERSION:-}" ]]; then
    if [[ "${PHP_VERSION}" =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
        image_line="${BASH_REMATCH[1]}"
    else
        image_line="${PHP_VERSION}"
    fi
    if requested="$(php_version_arg "$@")"; then
        if [[ "${requested}" =~ ^([0-9]+\.[0-9]+) ]]; then
            requested_line="${BASH_REMATCH[1]}"
        else
            requested_line="${requested}"
        fi
        if [[ "${requested_line}" != "${image_line}" || "${requested}" != "${image_line}" ]]; then
            echo "This tpc binary runs PHP ${PHP_VERSION}." >&2
            echo "php-builder must use --php-version=${image_line} so it downloads that same patch." >&2
            exit 1
        fi
    else
        cmd+=(--php-version="${image_line}")
    fi
fi
if ! has_flag --sapi "$@"; then
    cmd+=(--sapi="${TYPEPHP_SAPI:-embed}")
fi
if [[ -n "${TYPEPHP_JOBS:-}" ]] && ! has_flag --job "$@" && ! has_flag -j "$@"; then
    cmd+=(--job="${TYPEPHP_JOBS}")
fi

status=0
"${cmd[@]}" || status=$?
/usr/local/bin/typephp-chown-output . || true
exit "${status}"
