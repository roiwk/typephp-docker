#!/usr/bin/env bash
# One entry for host-path compiles.
# shared:        dynamic libphp.so
# static:        full-static SDK when TYPEPHP_EXTENSIONS is unset
# php-builder:   private PHP, zts off unless TYPEPHP_ZTS is set
# project:       an existing YAML, keeping its sapi (cli/fpm are not rewritten to embed)
# laravel/webman: example YAML's php-builder (private static PHP, zts off)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${TYPEPHP_IMAGE:-typephp:latest}"

usage() {
    cat <<'EOF'
用法: scripts/compile.sh <目标> [项目目录] [源文件]

  shared                动态链接镜像里的 libphp.so。源文件默认 hello.php
  static                完全静态 SDK，得到单个 ELF。不要设置 TYPEPHP_EXTENSIONS。
                        TYPEPHP_EXTENSIONS=redis 时改为把该扩展编进私有 PHP（zts 默认 off）
                        含 sapi: cli/fpm 或 php-builder 的 YAML 请用 project
  php-builder           私有 PHP，zts 默认 off。源文件默认 hello.php
  project               编译项目里已有的 YAML，默认 project.yml。保留其中的 sapi
  laravel-cli           示例 YAML，产物 build/laravel（artisan）
  laravel-fpm           示例 YAML，产物 build/laravel-fpm
  laravel-release       FPM 发布包，产物 build/laravel-fpm
  laravel-cli-release   artisan 发布包，产物 build/laravel
  webman                示例 YAML，产物 build/webman
  webman-release        发布包，产物 build/webman

项目目录默认是当前目录。镜像用 TYPEPHP_IMAGE，默认 typephp:latest。
示例 YAML 只在项目里还没有同名文件时复制。TYPEPHP_EXTENSIONS 会写进已有
php-builder.extensions（逗号分隔；空、none、[] 表示空名单）。
laravel / webman / project 按 YAML 的 php-builder 编译，不使用 static 的 SDK。
webman 会改 config/app.php：日志和 pid 写到二进制所在目录下的 runtime，不写死目录名。
laravel 会改 bootstrap/app.php：日志、缓存、session、上传写到二进制所在目录下的 storage。
EOF
}

extensions_yaml_value() {
    local raw="${TYPEPHP_EXTENSIONS}"
    local lower item out=""
    lower="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "${lower}" in
        ""|none|base|minimal|-|"[]")
            printf '%s' "[]"
            return
            ;;
    esac
    local IFS=','
    local items
    read -ra items <<<"${raw}"
    for item in "${items[@]}"; do
        item="${item//[[:space:]]/}"
        [[ -z "${item}" ]] && continue
        if [[ -n "${out}" ]]; then
            out+=", "
        fi
        out+="${item}"
    done
    printf '[%s]' "${out}"
}

apply_extensions() {
    local file="$1"
    [[ -v TYPEPHP_EXTENSIONS ]] || return 0
    if ! grep -q '^php-builder:' "${file}"; then
        echo "${file} 没有 php-builder，不能写入 TYPEPHP_EXTENSIONS" >&2
        exit 2
    fi
    if ! grep -q '^[[:space:]]*extensions:' "${file}"; then
        echo "${file} 没有 extensions 行" >&2
        exit 2
    fi
    local value tmp
    value="$(extensions_yaml_value)"
    tmp="$(mktemp)"
    awk -v val="${value}" '
        !done && $1 == "extensions:" {
            sub(/extensions:.*/, "extensions: " val)
            done = 1
        }
        { print }
    ' "${file}" >"${tmp}"
    mv "${tmp}" "${file}"
    echo "扩展: ${file} -> extensions: ${value}"
}

patch_extensions() {
    local yaml="$1"
    local path="${project}/${yaml}"
    [[ -v TYPEPHP_EXTENSIONS ]] || return 0
    if grep -q '^php-builder:' "${path}"; then
        apply_extensions "${path}"
        return
    fi
    local inc
    inc="$(awk '/^include:/{print $2; exit}' "${path}")"
    if [[ -n "${inc}" && -f "${project}/${inc}" ]]; then
        patch_extensions "${inc}"
        return
    fi
    echo "${path} 没有 php-builder，不能写入 TYPEPHP_EXTENSIONS" >&2
    exit 2
}

yaml_output() {
    local file="$1"
    local out inc
    out="$(awk '/^output:/{print $2; exit}' "${file}")"
    if [[ -n "${out}" ]]; then
        printf '%s' "${out}"
        return
    fi
    inc="$(awk '/^include:/{print $2; exit}' "${file}")"
    if [[ -n "${inc}" && -f "${project}/${inc}" ]]; then
        yaml_output "${project}/${inc}"
        return
    fi
    printf '%s' "（见 ${file} 的 output）"
}

copy_examples() {
    local framework="$1"
    shift
    local file src dest
    for file in "$@"; do
        src="${ROOT}/examples/frameworks/${framework}/${file}"
        dest="${project}/${file}"
        if [[ -e "${dest}" ]]; then
            echo "保留已有 ${file}"
            continue
        fi
        cp "${src}" "${dest}"
        echo "写入示例 ${framework}/${file}"
    done
}

ensure_artisan_php() {
    local path="${project}/artisan.php"
    if [[ ! -f "${project}/artisan" ]]; then
        echo "找不到 ${project}/artisan，请在 Laravel 项目根目录执行" >&2
        exit 2
    fi
    if [[ ! -f "${path}" ]]; then
        printf '%s\n' '#!/usr/bin/env php' '<?php' '' 'require __DIR__ . "/artisan";' >"${path}"
    fi
    chmod 755 "${path}"
}

ensure_webman() {
    if [[ ! -f "${project}/start.php" ]]; then
        echo "找不到 ${project}/start.php，请在 Webman 项目根目录执行" >&2
        exit 2
    fi
    chmod 755 "${project}/start.php"
}

# Logs follow the executable. The binary may live in any directory, so the
# path is dirname(PHP_BINARY), not a fixed build/ folder. php start.php keeps
# the project runtime directory.
patch_webman_runtime() {
    local file="${project}/config/app.php"
    if [[ ! -f "${file}" ]]; then
        echo "找不到 ${file}，无法设置 runtime 路径" >&2
        exit 2
    fi
    python3 - "${file}" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "dirname(PHP_BINARY)" in text:
    print(f"保留已有 runtime_path: {path}")
    raise SystemExit(0)
pattern = re.compile(
    r"^([ \t]*)'runtime_path'\s*=>\s*base_path\(false\)\s*\.\s*DIRECTORY_SEPARATOR\s*\.\s*'runtime'\s*,\s*$",
    re.M,
)
if not pattern.search(text):
    if "runtime_path" not in text:
        print(f"{path} 没有 runtime_path", file=sys.stderr)
        raise SystemExit(2)
    print(f"保留已有 runtime_path: {path}")
    raise SystemExit(0)

def repl(match):
    indent = match.group(1)
    return (
        f"{indent}'runtime_path' => (PHP_BINARY !== '' && !preg_match('#(?:^|/)php(?:\\d+(?:\\.\\d+)*)?$#', PHP_BINARY))\n"
        f"{indent}    ? dirname(PHP_BINARY) . DIRECTORY_SEPARATOR . 'runtime'\n"
        f"{indent}    : base_path(false) . DIRECTORY_SEPARATOR . 'runtime',"
    )

path.write_text(pattern.sub(repl, text, count=1))
print(f"runtime 跟随二进制: {path}")
PY
}

# Writable Laravel files follow the executable. php artisan keeps the project
# storage directory. The directory name is not fixed to build/.
patch_laravel_storage() {
    local file="${project}/bootstrap/app.php"
    if [[ ! -f "${file}" ]]; then
        echo "找不到 ${file}，无法设置 storage 路径" >&2
        exit 2
    fi
    python3 - "${file}" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "useStoragePath" in text:
    print(f"保留已有 storage 路径: {path}")
    raise SystemExit(0)
needle = "return Application::configure"
if needle not in text or "->create();" not in text:
    print(f"{path} 不是 Laravel bootstrap，未改 storage 路径", file=sys.stderr)
    raise SystemExit(2)
text = text.replace(needle, "$app = Application::configure", 1)
idx = text.rfind("->create();")
snippet = """->create();

if (PHP_BINARY !== '' && !preg_match('#(?:^|/)php(?:\\d+(?:\\.\\d+)*)?$#', PHP_BINARY)) {
    $storage = dirname(PHP_BINARY) . DIRECTORY_SEPARATOR . 'storage';
    foreach (['app/public', 'app/private', 'framework/cache/data', 'framework/sessions', 'framework/views', 'logs'] as $dir) {
        $dir = $storage . DIRECTORY_SEPARATOR . $dir;
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
    }
    $app->useStoragePath($storage);
}

return $app;"""
path.write_text(text[:idx] + snippet + text[idx + len("->create();"):])
print(f"storage 跟随二进制: {path}")
PY
}

ensure_vendor() {
    if [[ -f "${project}/vendor/autoload.php" ]]; then
        return 0
    fi
    if [[ ! -f "${project}/composer.json" ]]; then
        echo "找不到 ${project}/vendor/autoload.php" >&2
        exit 2
    fi
    echo "安装 Composer 依赖: ${project}"
    docker run --rm \
        -v "${project}:${project}" \
        -w "${project}" \
        -e COMPOSER_ALLOW_SUPERUSER=1 \
        -e HOST_UID="$(id -u)" \
        -e HOST_GID="$(id -g)" \
        "${IMAGE}" \
        bash -c 'composer install --no-interaction --no-dev --classmap-authoritative && typephp-chown-output .'
}

effective_sapi() {
    local file="$1"
    local sapi inc
    sapi="$(awk '/^sapi:/{print $2; exit}' "${file}")"
    if [[ -n "${sapi}" ]]; then
        printf '%s' "${sapi}"
        return
    fi
    inc="$(awk '/^include:/{print $2; exit}' "${file}")"
    if [[ -n "${inc}" && -f "${project}/${inc}" ]]; then
        effective_sapi "${project}/${inc}"
    fi
}

# An FPM binary with no embedded PHP omits opcode_unserialize and then fails
# to link typephp_opcache_load. One tiny embedded file pulls that object in.
prepare_fpm_link() {
    local yaml="$1"
    local path="${project}/${yaml}"
    [[ "$(effective_sapi "${path}")" == "fpm" ]] || return 0
    if [[ ! -f "${project}/typephp-fpm.php" ]]; then
        printf '%s\n' '<?php' '// Keeps the FPM link from dropping opcode_unserialize.' >"${project}/typephp-fpm.php"
    fi
    python3 - "${path}" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if re.search(r"(?m)^\s*-\s*typephp-fpm\.php\s*$", text):
    print(f"保留已有 FPM 嵌入: {path}")
    raise SystemExit(0)
if re.search(r"(?m)^embedded-files:\s*$", text):
    text = re.sub(r"(?m)^(embedded-files:\s*)$", r"\1\n  - typephp-fpm.php", text, count=1)
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "embedded-files:\n  - typephp-fpm.php\n"
path.write_text(text)
print(f"FPM 嵌入 typephp-fpm.php: {path}")
PY
}

compile_yaml() {
    local yaml="$1"
    local output="$2"
    unset TYPEPHP_LINK
    prepare_fpm_link "${yaml}"
    echo "编译 ${yaml} -> ${project}/${output} （YAML php-builder，zts off）"
    "${ROOT}/scripts/compile-hostpath.sh" "${project}" tpc "${yaml}"
    echo "产物: ${project}/${output}"
}

yaml_needs_project_target() {
    local file="$1"
    grep -Eq '^sapi:.*(cli|fpm)|^php-builder:' "${file}"
}

compile_link() {
    local link="$1"
    if [[ -z "${source}" ]]; then
        source="hello.php"
    fi
    if [[ "${source}" != /* ]]; then
        source="${project}/${source}"
    fi
    if [[ ! -f "${source}" ]]; then
        echo "找不到 ${source}" >&2
        exit 2
    fi
    local rel="${source#"${project}/"}"
    case "${link}" in
        shared)
            unset TYPEPHP_LINK
            echo "动态链接 ${rel} -> ${project}/${rel%.php}"
            ;;
        static)
            if [[ "${rel}" == *.yml || "${rel}" == *.yaml ]] && yaml_needs_project_target "${source}"; then
                echo "${rel} 含 cli/fpm 或 php-builder。请用: scripts/compile.sh project ${project} ${rel}" >&2
                exit 2
            fi
            export TYPEPHP_LINK=static
            if [[ -n "${TYPEPHP_EXTENSIONS+x}" ]]; then
                echo "静态编译 ${rel}：扩展编进私有 PHP（zts 默认 off）"
            else
                echo "完全静态 SDK 编译 ${rel}"
            fi
            ;;
        php-builder)
            export TYPEPHP_LINK=php-builder
            echo "私有 PHP 编译 ${rel}（zts 默认 off）"
            ;;
    esac
    "${ROOT}/scripts/compile-hostpath.sh" "${project}" tpc "${rel}"
}

compile_project() {
    local yaml="${source:-project.yml}"
    if [[ "${yaml}" == /* ]]; then
        echo "YAML 请使用相对项目目录的路径" >&2
        exit 2
    fi
    if [[ ! -f "${project}/${yaml}" ]]; then
        echo "找不到 ${project}/${yaml}" >&2
        exit 2
    fi
    if [[ -f "${project}/composer.json" ]]; then
        ensure_vendor
    fi
    patch_extensions "${yaml}"
    if [[ -f "${project}/start.php" && -f "${project}/config/app.php" ]]; then
        patch_webman_runtime
    fi
    if [[ -f "${project}/bootstrap/app.php" ]] && grep -q 'Application::configure' "${project}/bootstrap/app.php"; then
        patch_laravel_storage
    fi
    compile_yaml "${yaml}" "$(yaml_output "${project}/${yaml}")"
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    if [[ $# -lt 1 ]]; then
        usage
        exit 2
    fi

    local target="$1"
    shift

    project="$(pwd)"
    source=""
    if [[ $# -ge 1 && -d "$1" ]]; then
        project="$(cd "$1" && pwd)"
        shift
    fi
    if [[ $# -ge 1 ]]; then
        source="$1"
        shift
    fi
    if [[ $# -ne 0 ]]; then
        usage
        exit 2
    fi

    case "${target}" in
        shared|static|php-builder)
            compile_link "${target}"
            ;;
        project|yml)
            compile_project
            ;;
        laravel|laravel-cli)
            ensure_artisan_php
            ensure_vendor
            copy_examples laravel project.yml project-cli.yml
            patch_extensions project-cli.yml
            patch_laravel_storage
            compile_yaml project-cli.yml "$(yaml_output "${project}/project-cli.yml")"
            ;;
        laravel-fpm)
            ensure_vendor
            copy_examples laravel project.yml php-fpm.conf
            patch_extensions project.yml
            patch_laravel_storage
            compile_yaml project.yml "$(yaml_output "${project}/project.yml")"
            ;;
        laravel-release)
            ensure_vendor
            copy_examples laravel project.yml project-release.yml php-fpm.conf
            patch_extensions project-release.yml
            patch_laravel_storage
            compile_yaml project-release.yml "$(yaml_output "${project}/project-release.yml")"
            ;;
        laravel-cli-release)
            ensure_artisan_php
            ensure_vendor
            copy_examples laravel project.yml project-cli.yml project-cli-release.yml
            patch_extensions project-cli-release.yml
            patch_laravel_storage
            compile_yaml project-cli-release.yml "$(yaml_output "${project}/project-cli-release.yml")"
            ;;
        webman)
            ensure_webman
            ensure_vendor
            copy_examples webman project.yml
            patch_extensions project.yml
            patch_webman_runtime
            compile_yaml project.yml "$(yaml_output "${project}/project.yml")"
            ;;
        webman-release)
            ensure_webman
            ensure_vendor
            copy_examples webman project.yml project-release.yml
            patch_extensions project-release.yml
            patch_webman_runtime
            compile_yaml project-release.yml "$(yaml_output "${project}/project-release.yml")"
            ;;
        *)
            usage
            exit 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
