#!/usr/bin/env bash
# Compile with a private static PHP embed (--php-builder).
# The binary does not need the image libphp.so. It still dynamically links
# system libraries such as libstdc++, GMP, and OpenSSL.
set -euo pipefail

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

cmd=(tpc "$@")
if ! has_flag --php-builder "$@"; then
    extensions="${TYPEPHP_EXTENSIONS:-}"
    if [[ -z "${extensions}" ]]; then
        ext_yaml="[]"
    else
        ext_yaml="[${extensions}]"
    fi
    cmd+=(--php-builder="extensions: ${ext_yaml}; zts: ${TYPEPHP_ZTS:-on}")
fi
if ! has_flag --sapi "$@"; then
    cmd+=(--sapi="${TYPEPHP_SAPI:-embed}")
fi
if [[ -n "${TYPEPHP_JOBS:-}" ]] && ! has_flag --job "$@" && ! has_flag -j "$@"; then
    cmd+=(--job="${TYPEPHP_JOBS}")
fi

exec "${cmd[@]}"
