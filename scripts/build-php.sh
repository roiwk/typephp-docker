#!/usr/bin/env bash
# Build PHP CLI + Embed SAPI (libphp.so) into /opt/php.
# TypePHP binary mode needs a ZTS build whose headers, php-config, and
# libphp.so all come from the same prefix.
set -euo pipefail

: "${PHP_VERSION:?PHP_VERSION is required}"
: "${PHP_SHA256:?PHP_SHA256 is required}"
: "${MAKE_JOBS:?MAKE_JOBS is required}"
: "${PHP_HOME:?PHP_HOME is required}"

src="/tmp/php-src"
tarball="/tmp/php-${PHP_VERSION}.tar.xz"

curl -fL --retry 5 --retry-delay 2 \
    -o "${tarball}" \
    "https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"
echo "${PHP_SHA256}  ${tarball}" | sha256sum -c -

rm -rf "${src}"
mkdir -p "${src}"
tar -xJf "${tarball}" -C "${src}" --strip-components=1
rm -f "${tarball}"

cd "${src}"
./buildconf --force
./configure \
    --prefix="${PHP_HOME}" \
    --libdir="${PHP_HOME}/lib" \
    --with-config-file-path="${PHP_HOME}/lib" \
    --with-config-file-scan-dir="${PHP_HOME}/lib/conf.d" \
    --enable-zts \
    --enable-embed=shared \
    --enable-cli \
    --disable-fpm \
    --disable-cgi \
    --disable-phpdbg \
    --enable-opcache \
    --without-pear \
    --with-openssl \
    --with-zlib \
    --with-curl \
    --enable-mbstring \
    --with-zip \
    --with-ffi \
    --enable-bcmath \
    --with-gmp \
    --enable-sockets \
    --with-sodium \
    --with-readline \
    --enable-pcntl \
    --with-sqlite3 \
    --with-pdo-sqlite

make -j"${MAKE_JOBS}"
make install

mkdir -p "${PHP_HOME}/lib/conf.d"
cat > "${PHP_HOME}/lib/php.ini" << 'EOF'
memory_limit=4G
precision=17
error_reporting=E_ALL
display_errors=1
display_startup_errors=1
log_errors=1
date.timezone=UTC
zend.assertions=1
opcache.enable=1
opcache.enable_cli=1
EOF

hash_header="${PHP_HOME}/include/php/ext/hash/php_hash.h"
if [[ -f "${hash_header}" ]] && grep -Fq 'char *base = ecalloc(' "${hash_header}"; then
    # php/php-src#22935: the header is valid C and invalid C++ until #22940.
    sed -i 's/char \*base = ecalloc(/char *base = (char *) ecalloc(/' "${hash_header}"
fi

if ! php -r 'exit(PHP_ZTS ? 0 : 1);'; then
    echo "PHP was built without ZTS" >&2
    exit 1
fi
test -x "${PHP_HOME}/bin/php-config"
test -f "${PHP_HOME}/lib/libphp.so"
php -v
php-config --version

rm -rf "${src}"
ldconfig
