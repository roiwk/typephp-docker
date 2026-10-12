#!/usr/bin/env bash
# Install the source packages `tpc --nano` reads beside its own binary.
# The self-hosted tpc looks for swoole/php-nano at /usr/local/php-nano and
# swoole/phpx at /usr/local/phpx (dirname of /usr/local/bin). It does not
# link libphp. --full-static and --php-builder are rejected.
set -euo pipefail

: "${PHPX_HOME:?PHPX_HOME is required}"
PHP_NANO_VERSION="${PHP_NANO_VERSION:-v1.1.0}"
PHP_NANO_SHA256="${PHP_NANO_SHA256:-f9d59c03b0cf6d1121ff3fe699fd00d7357b28df8f2ae9633a0448c7f1d2c064}"

if [[ ! -f "${PHPX_HOME}/composer.json" ]]; then
    echo "PHPX source at ${PHPX_HOME} has no composer.json" >&2
    exit 1
fi
ln -sfn "${PHPX_HOME}" /usr/local/phpx

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

archive="${workdir}/php-nano.tar.gz"
attempt=0
until curl -fL --retry 3 --retry-all-errors --retry-delay 2 \
    -o "${archive}" \
    "https://github.com/swoole/php-nano/archive/refs/tags/${PHP_NANO_VERSION}.tar.gz"
do
    attempt=$((attempt + 1))
    if [[ "${attempt}" -ge 8 ]]; then
        echo "failed to download swoole/php-nano ${PHP_NANO_VERSION}" >&2
        exit 1
    fi
    sleep $((attempt * 3))
done
echo "${PHP_NANO_SHA256}  ${archive}" | sha256sum -c -

rm -rf /usr/local/php-nano
mkdir -p /usr/local/php-nano
tar -xzf "${archive}" -C /usr/local/php-nano --strip-components=1

php -r '
$check = static function (string $path, string $name): int {
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || ($data["name"] ?? "") !== $name) {
        fwrite(STDERR, "$path is not $name\n");
        exit(1);
    }
    $native = $data["extra"]["typephp-native"] ?? null;
    if (!is_array($native) || !is_int($native["abi"] ?? null)) {
        fwrite(STDERR, "$path has no typephp-native abi\n");
        exit(1);
    }
    $root = dirname($path);
    foreach ($native["sources"] ?? [] as $source) {
        if (!is_string($source) || !is_file($root . "/" . $source)) {
            fwrite(STDERR, "missing $name source $source\n");
            exit(1);
        }
    }
    foreach ($native["include-dirs"] ?? [] as $dir) {
        if (!is_string($dir) || !is_dir($root . "/" . $dir)) {
            fwrite(STDERR, "missing $name include $dir\n");
            exit(1);
        }
    }
    return $native["abi"];
};
$nano = $check("/usr/local/php-nano/composer.json", "swoole/php-nano");
$phpx = $check("/usr/local/phpx/composer.json", "swoole/phpx");
if ($nano !== $phpx) {
    fwrite(STDERR, "ABI mismatch: php-nano=$nano phpx=$phpx\n");
    exit(1);
}
'
