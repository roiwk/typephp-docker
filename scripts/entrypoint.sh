#!/usr/bin/env bash
# TYPEPHP_LINK selects how `tpc ...` links the program:
#   shared      dynamic libphp.so / libphpx.so (default)
#   static      tpc --full-static
#   php-builder private static PHP embed
set -euo pipefail

if [[ "${1:-}" == "tpc" ]]; then
    shift
    case "${TYPEPHP_LINK:-shared}" in
        static|full-static)
            exec /usr/local/bin/tpc-static "$@"
            ;;
        php-builder|private)
            exec /usr/local/bin/tpc-private "$@"
            ;;
        shared)
            exec tpc "$@"
            ;;
        *)
            echo "TYPEPHP_LINK must be shared, static, or php-builder" >&2
            exit 2
            ;;
    esac
fi

exec "$@"
