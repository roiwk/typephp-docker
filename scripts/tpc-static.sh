#!/usr/bin/env bash
# Compile a program with tpc --full-static.
# The result is linked against $PHPX_HOME/full-static/sdk (libphp.a, libphpx.a, musl).
set -euo pipefail

sdk="${PHPX_HOME}/full-static/sdk"
if [[ ! -s "${sdk}/lib/libphp.a" || ! -s "${sdk}/lib/libphpx.a" ]]; then
    echo "full-static SDK is not installed at ${sdk}" >&2
    exit 1
fi

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

# Input path comes first. tpc treats a bare token after --compiler as a source file,
# so the compiler command is passed as --compiler=<path>.
cmd=(tpc "$@")
if ! has_flag --full-static "$@"; then
    cmd+=(--full-static)
fi
if ! has_flag --compiler "$@"; then
    cmd+=(--compiler="${TYPEPHP_COMPILER:-/usr/bin/clang}")
fi
if [[ -n "${TYPEPHP_JOBS:-}" ]] && ! has_flag --job "$@" && ! has_flag -j "$@"; then
    cmd+=(--job="${TYPEPHP_JOBS}")
fi

exec "${cmd[@]}"
