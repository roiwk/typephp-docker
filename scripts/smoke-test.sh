#!/usr/bin/env bash
set -euo pipefail

: "${MAKE_JOBS:?MAKE_JOBS is required}"
: "${PHP_HOME:?PHP_HOME is required}"
: "${PHPX_HOME:?PHPX_HOME is required}"

php -v
php -r 'if (!PHP_ZTS) { fwrite(STDERR, "expected ZTS PHP\n"); exit(1); }'
test -f "${PHP_HOME}/lib/libphp.so"
test -f "${PHPX_HOME}/lib/libphpx.so"
tpc --version
ldd /usr/local/bin/tpc | grep -E 'libphp\.so|libphpx\.so'

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
cat > "${workdir}/hello.php" << 'EOF'
<?php

function main(): void
{
    echo "Hello World!\n";
}
EOF

cd "${workdir}"
tpc hello.php --job "${MAKE_JOBS}" --no-progress
test -x "${workdir}/hello"
"${workdir}/hello" | grep -F 'Hello World!'
