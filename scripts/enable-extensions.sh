#!/usr/bin/env bash
# Build and enable extra PHP extensions for this container.
# TYPEPHP_EXTENSIONS is a comma-separated list, for example redis,swoole,gd.
# Shared mode installs them as .so files for the image libphp.so.
# php-builder, and static with TYPEPHP_EXTENSIONS, only install the libraries
# that the private PHP compile needs. tpc then links those extensions statically.
set -euo pipefail

# shellcheck source=/usr/local/bin/typephp-ext-mode.sh
source /usr/local/bin/typephp-ext-mode.sh

: "${PHP_HOME:?PHP_HOME is required}"
: "${PHP_VERSION:?PHP_VERSION is required}"
: "${PHP_SHA256:?PHP_SHA256 is required}"

cache="${TYPEPHP_EXT_CACHE:-/var/cache/typephp-ext}"
jobs="${TYPEPHP_JOBS:-2}"
export DEBIAN_FRONTEND=noninteractive
export PATH="${PHP_HOME}/bin:${PATH}"

case "${TYPEPHP_LINK:-shared}" in
    static|full-static|php-builder|private)
        prepare_only=1
        ;;
    shared)
        prepare_only=0
        ;;
    *)
        echo "TYPEPHP_LINK must be shared, static, or php-builder" >&2
        exit 2
        ;;
esac

apt_updated=0
install_packages() {
    local missing=() pkg
    for pkg in "$@"; do
        dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done
    if ((${#missing[@]} == 0)); then
        return 0
    fi
    if ((apt_updated == 0)); then
        apt-get update
        apt_updated=1
    fi
    apt-get install -y --no-install-recommends "${missing[@]}"
}

ensure_php_src() {
    local dest="${cache}/php-${PHP_VERSION}"
    if [[ -f "${dest}/ext/standard/config.m4" ]]; then
        printf '%s\n' "${dest}"
        return 0
    fi
    mkdir -p "${cache}"
    local tarball="${cache}/php-${PHP_VERSION}.tar.xz"
    if [[ ! -f "${tarball}" ]]; then
        curl -fL --retry 5 --retry-delay 2 \
            -o "${tarball}" \
            "https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"
    fi
    echo "${PHP_SHA256}  ${tarball}" | sha256sum -c - >&2
    rm -rf "${dest}"
    mkdir -p "${dest}"
    tar -xJf "${tarball}" -C "${dest}" --strip-components=1
    printf '%s\n' "${dest}"
}

extension_loaded() {
    local name="$1"
    php -m | tr '[:upper:]' '[:lower:]' | grep -qx "${name}"
}

write_ini() {
    local name="$1"
    mkdir -p "${PHP_HOME}/lib/conf.d"
    printf 'extension=%s\n' "${name}" > "${PHP_HOME}/lib/conf.d/20-${name}.ini"
}

# kind, source dir or pecl name, version, configure args, apt packages
describe_extension() {
    local name="$1"
    ext_kind=""
    ext_src=""
    ext_version=""
    ext_configure=""
    ext_packages=""
    case "${name}" in
        bz2)
            ext_kind=bundled; ext_src=bz2; ext_configure="--with-bz2"; ext_packages="libbz2-dev"
            ;;
        exif)
            ext_kind=bundled; ext_src=exif; ext_configure="--enable-exif"
            ;;
        ftp)
            ext_kind=bundled; ext_src=ftp; ext_configure="--enable-ftp"
            ;;
        gd)
            ext_kind=bundled; ext_src=gd
            ext_configure="--enable-gd --with-jpeg --with-freetype --with-webp"
            ext_packages="libpng-dev libjpeg-turbo8-dev libfreetype6-dev libwebp-dev pkg-config"
            ;;
        gettext)
            ext_kind=bundled; ext_src=gettext; ext_configure="--with-gettext"
            ;;
        intl)
            ext_kind=bundled; ext_src=intl; ext_configure="--enable-intl"
            ext_packages="libicu-dev pkg-config"
            ;;
        pdo_pgsql)
            ext_kind=bundled; ext_src=pdo_pgsql; ext_configure="--with-pdo-pgsql"
            ext_packages="libpq-dev"
            ;;
        pgsql)
            ext_kind=bundled; ext_src=pgsql; ext_configure="--with-pgsql"
            ext_packages="libpq-dev"
            ;;
        soap)
            ext_kind=bundled; ext_src=soap; ext_configure="--enable-soap"
            ext_packages="libxml2-dev"
            ;;
        xsl)
            ext_kind=bundled; ext_src=xsl; ext_configure="--with-xsl"
            ext_packages="libxslt1-dev libxml2-dev pkg-config"
            ;;
        redis)
            ext_kind=pecl; ext_src=redis; ext_version=6.3.0
            ext_configure="--enable-redis"
            ext_packages="libhiredis-dev pkg-config"
            ;;
        swoole)
            ext_kind=pecl; ext_src=swoole; ext_version=6.2.3
            ext_configure="--enable-openssl --enable-swoole-curl --enable-brotli --enable-zstd"
            ext_packages="libssl-dev libcurl4-openssl-dev libbrotli-dev libzstd-dev pkg-config"
            ;;
        yaml)
            ext_kind=pecl; ext_src=yaml; ext_version=2.3.0
            ext_configure="--with-yaml"
            ext_packages="libyaml-dev pkg-config"
            ;;
        imagick)
            ext_kind=pecl; ext_src=imagick; ext_version=3.8.1
            ext_packages="libmagickwand-dev pkg-config"
            ;;
        mongodb)
            ext_kind=pecl; ext_src=mongodb; ext_version=2.5.4
            ext_packages="libmongoc-dev libbson-dev pkg-config"
            ;;
        mysqli)
            ext_kind=builder
            ;;
        pdo_mysql)
            ext_kind=builder
            ;;
        pcntl)
            ext_kind=bundled; ext_src=pcntl; ext_configure="--enable-pcntl"
            ;;
        posix)
            ext_kind=bundled; ext_src=posix; ext_configure="--enable-posix"
            ;;
        *)
            return 1
            ;;
    esac
}

install_from_cache() {
    local name="$1" version="$2"
    local cached="${cache}/so/${PHP_VERSION}/${name}-${version}.so"
    local dest
    dest="$(php-config --extension-dir)/${name}.so"
    if [[ ! -s "${cached}" ]]; then
        return 1
    fi
    mkdir -p "$(dirname "${dest}")"
    cp -a "${cached}" "${dest}"
    write_ini "${name}"
}

remember_installed() {
    local name="$1" version="$2"
    local dest cached
    dest="$(php-config --extension-dir)/${name}.so"
    cached="${cache}/so/${PHP_VERSION}/${name}-${version}.so"
    mkdir -p "$(dirname "${cached}")"
    cp -a "${dest}" "${cached}"
}

build_bundled() {
    local name="$1" src_dir="$2" configure="$3"
    local php_src build_dir
    php_src="$(ensure_php_src)"
    build_dir="${cache}/build/${PHP_VERSION}/${name}"
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"
    cp -a "${php_src}/ext/${src_dir}/." "${build_dir}/"
    (
        cd "${build_dir}"
        phpize
        ./configure --with-php-config="${PHP_HOME}/bin/php-config" ${configure}
        make -j"${jobs}"
        make install
    )
}

build_pecl() {
    local name="$1" version="$2" configure="$3"
    local tarball="${cache}/src/${name}-${version}.tgz"
    local build_dir="${cache}/build/${PHP_VERSION}/${name}-${version}"
    mkdir -p "${cache}/src"
    if [[ ! -s "${tarball}" ]]; then
        curl -fL --retry 5 --retry-delay 2 \
            -o "${tarball}" \
            "https://pecl.php.net/get/${name}-${version}.tgz"
    fi
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"
    tar -xzf "${tarball}" -C "${build_dir}" --strip-components=1
    (
        cd "${build_dir}"
        phpize
        ./configure --with-php-config="${PHP_HOME}/bin/php-config" ${configure}
        make -j"${jobs}"
        make install
    )
}

enable_one() {
    local name="$1"
    if extension_loaded "${name}"; then
        echo "extension ${name} is already loaded"
        return 0
    fi
    if ! describe_extension "${name}"; then
        echo "unsupported extension: ${name}" >&2
        echo "supported: bz2, exif, ftp, gd, gettext, imagick, intl, mongodb, mysqli, pcntl, pdo_mysql, pdo_pgsql, pgsql, posix, redis, soap, swoole, xsl, yaml" >&2
        exit 1
    fi
    if [[ -n "${ext_packages}" ]]; then
        # shellcheck disable=SC2086
        install_packages ${ext_packages}
    fi
    if ((prepare_only == 1)); then
        echo "libraries for ${name} are ready for a private PHP"
        return 0
    fi
    if [[ "${ext_kind}" == builder ]]; then
        echo "${name} is compiled into a private PHP." >&2
        echo "Set TYPEPHP_LINK=static or TYPEPHP_LINK=php-builder." >&2
        exit 1
    fi
    local version="${ext_version:-${PHP_VERSION}}"
    if install_from_cache "${name}" "${version}" && extension_loaded "${name}"; then
        echo "enabled cached extension ${name}"
        return 0
    fi
    if [[ "${ext_kind}" == bundled ]]; then
        build_bundled "${name}" "${ext_src}" "${ext_configure}"
    else
        build_pecl "${name}" "${ext_version}" "${ext_configure}"
    fi
    write_ini "${name}"
    if ! extension_loaded "${name}"; then
        echo "extension ${name} was installed but PHP did not load it" >&2
        php -m >&2 || true
        exit 1
    fi
    remember_installed "${name}" "${version}"
    echo "enabled extension ${name}"
}

mkdir -p "${cache}"
extension_selection="$(typephp_extension_selection)"
if [[ "${extension_selection}" == omit || "${extension_selection}" == minimal ]]; then
    exit 0
fi
IFS=',' read -ra requested <<< "${extension_selection}"
for name in "${requested[@]}"; do
    name="${name,,}"
    if [[ -z "${name}" ]]; then
        continue
    fi
    enable_one "${name}"
done
