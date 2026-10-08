#!/usr/bin/env bash
# Build libphpx.so against the PHP prefix in PHP_HOME.
# TypePHP needs the PHPX source tree (headers and src/misc), not only the .so.
set -euo pipefail

: "${PHPX_REF:?PHPX_REF is required}"
: "${PHPX_HOME:?PHPX_HOME is required}"
: "${PHP_HOME:?PHP_HOME is required}"
: "${MAKE_JOBS:?MAKE_JOBS is required}"

rm -rf "${PHPX_HOME}"
mkdir -p "${PHPX_HOME}"
git -C "${PHPX_HOME}" init
git -C "${PHPX_HOME}" remote add origin https://github.com/swoole/phpx.git
git -C "${PHPX_HOME}" fetch --depth 1 origin "${PHPX_REF}"
git -C "${PHPX_HOME}" checkout --detach FETCH_HEAD
rm -rf "${PHPX_HOME}/.git"

cmake -S "${PHPX_HOME}" -B "${PHPX_HOME}/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    -DBUILD_EXT=OFF \
    -Dphp_dir="${PHP_HOME}"
cmake --build "${PHPX_HOME}/build" --target phpx --parallel "${MAKE_JOBS}"

test -f "${PHPX_HOME}/lib/libphpx.so"
test -f "${PHPX_HOME}/CMakeLists.txt"
test -d "${PHPX_HOME}/include"
test -d "${PHPX_HOME}/src/misc"

rm -rf "${PHPX_HOME}/build"
ldconfig
