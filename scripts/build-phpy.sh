#!/usr/bin/env bash
# phpy is required by the tpc binary: its embedded typephp_tpc module
# refuses to start unless the phpy extension is already loaded.
set -euo pipefail

: "${PHPY_REF:?PHPY_REF is required}"
: "${PHP_HOME:?PHP_HOME is required}"
: "${MAKE_JOBS:?MAKE_JOBS is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3 python3-dev
rm -rf /var/lib/apt/lists/*

rm -rf /opt/phpy
mkdir -p /opt/phpy
git -C /opt/phpy init
git -C /opt/phpy remote add origin https://github.com/swoole/phpy.git
git -C /opt/phpy fetch --depth 1 origin "${PHPY_REF}"
git -C /opt/phpy checkout --detach FETCH_HEAD
rm -rf /opt/phpy/.git

cd /opt/phpy
phpize
./configure
make -j"${MAKE_JOBS}"
test -f modules/phpy.so

mkdir -p "${PHP_HOME}/lib/conf.d"
cat > "${PHP_HOME}/lib/conf.d/90-phpy.ini" << EOF
extension=/opt/phpy/modules/phpy.so
phpy.enable_operator_overloading=0
EOF

php --ri phpy
cd /
