#!/usr/bin/env bash
# TYPEPHP_LINK selects how `tpc ...` links the program:
#   shared      dynamic libphp.so / libphpx.so (default)
#   static      tpc --full-static
#   php-builder private static PHP embed
set -euo pipefail

# shellcheck source=/usr/local/bin/typephp-ext-mode.sh
source /usr/local/bin/typephp-ext-mode.sh

extension_selection="$(typephp_extension_selection)"
if [[ "${extension_selection}" != omit && "${extension_selection}" != minimal ]]; then
    TYPEPHP_EXTENSIONS="${extension_selection}" /usr/local/bin/typephp-ext
fi

run_tpc() {
    local status=0
    case "${TYPEPHP_LINK:-shared}" in
        static|full-static)
            /usr/local/bin/tpc-static "$@" || status=$?
            ;;
        php-builder|private)
            /usr/local/bin/tpc-private "$@" || status=$?
            ;;
        shared)
            tpc "$@" || status=$?
            ;;
        *)
            echo "TYPEPHP_LINK must be shared, static, or php-builder" >&2
            exit 2
            ;;
    esac
    /usr/local/bin/typephp-chown-output . || true
    exit "${status}"
}

# No args: same result as the image CMD.
if [[ $# -eq 0 ]]; then
    run_tpc --version
fi

# bash `exec` parses -c, -l and -a as its own options. A container command of
# `-c ...` therefore never runs a program named -c; it looks up the next word
# and can fail with `exec: c: not found`. Flags are tpc options.
if [[ "${1}" == "tpc" ]]; then
    shift
    run_tpc "$@"
fi

if [[ "${1}" == -* ]]; then
    run_tpc "$@"
fi

if [[ ! -x "${1}" ]] && ! command -v -- "${1}" >/dev/null 2>&1; then
    echo "找不到命令: ${1}" >&2
    echo "编译: tpc hello.php" >&2
    echo "静态: tpc-static hello.php    或    TYPEPHP_LINK=static tpc hello.php" >&2
    echo "版本: tpc --version" >&2
    exit 127
fi

# `--` keeps a program whose name starts with '-' from being read as an exec option.
exec -- "$@"
