#!/usr/bin/env bash
# Compile a project in Docker with the directory mounted at its host path.
# tpc records __DIR__ and __FILE__ as the path it sees at compile time.
# Mounting the project at /src makes the binary require /src/... and fail on the host.
# Mounting it at the same absolute path makes those paths valid on the host.
set -euo pipefail

IMAGE="${TYPEPHP_IMAGE:-typephp:latest}"

if [[ $# -ge 1 && -d "$1" ]]; then
    PROJECT="$(cd "$1" && pwd)"
    shift
else
    PROJECT="$(pwd)"
fi

if [[ $# -eq 0 ]]; then
    echo "用法: scripts/compile-hostpath.sh [项目目录] tpc project.yml [tpc 参数...]" >&2
    echo "在项目目录里也可以: scripts/compile-hostpath.sh tpc project-cli.yml" >&2
    exit 2
fi

env_args=()
for name in TYPEPHP_LINK TYPEPHP_EXTENSIONS TYPEPHP_SAPI TYPEPHP_ZTS TYPEPHP_JOBS TYPEPHP_COMPILER TYPEPHP_EXT_CACHE; do
    if [[ -n "${!name+x}" ]]; then
        env_args+=(-e "${name}=${!name}")
    fi
done

docker run --rm \
    -v "${PROJECT}:${PROJECT}" \
    -w "${PROJECT}" \
    -v typephp-php:/root/.typephp \
    -v typephp-ext:/var/cache/typephp-ext \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    "${env_args[@]}" \
    "${IMAGE}" \
    bash -c '
set -euo pipefail
status=0
if [[ "${1:-}" == tpc ]]; then
    shift
    case "${TYPEPHP_LINK:-shared}" in
        static|full-static) /usr/local/bin/tpc-static "$@" || status=$? ;;
        php-builder|private) /usr/local/bin/tpc-private "$@" || status=$? ;;
        shared) tpc "$@" || status=$? ;;
        *)
            echo "TYPEPHP_LINK must be shared, static, or php-builder" >&2
            exit 2
            ;;
    esac
else
    "$@" || status=$?
fi
if [[ -x /usr/local/bin/typephp-chown-output ]]; then
    /usr/local/bin/typephp-chown-output . || true
elif [[ "$(id -u)" -eq 0 && -n "${HOST_UID:-}" ]]; then
    find . -xdev -uid 0 -exec chown -h "${HOST_UID}:${HOST_GID}" {} +
fi
exit "${status}"
' bash "$@"
