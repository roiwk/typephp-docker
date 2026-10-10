#!/usr/bin/env bash
# Compile a program with tpc --full-static.
# The result is linked against $PHPX_HOME/full-static/sdk (libphp.a, libphpx.a, musl).
# An explicit TYPEPHP_EXTENSIONS value, including an empty list, is compiled
# into a private static PHP instead (same path as tpc-private).
set -euo pipefail

# shellcheck source=/usr/local/bin/typephp-ext-mode.sh
source /usr/local/bin/typephp-ext-mode.sh

extension_selection="$(typephp_extension_selection)"
if [[ "${extension_selection}" != omit ]]; then
    if [[ "${extension_selection}" == minimal ]]; then
        echo "TYPEPHP_EXTENSIONS names no extensions, so this static build uses a private base PHP." >&2
        export TYPEPHP_EXTENSIONS=
    else
        echo "TYPEPHP_EXTENSIONS is set, so this static build compiles those extensions into a private PHP." >&2
        export TYPEPHP_EXTENSIONS="${extension_selection}"
    fi
    echo "The prebuilt full-static SDK keeps its own extension set and is not used for this build." >&2
    echo "The binary does not need libphp.so. OpenSSL, GMP and similar libraries stay dynamic." >&2
    status=0
    /usr/local/bin/tpc-private "$@" || status=$?
    /usr/local/bin/typephp-chown-output . || true
    exit "${status}"
fi

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

status=0
"${cmd[@]}" || status=$?
/usr/local/bin/typephp-chown-output . || true
exit "${status}"
