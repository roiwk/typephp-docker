# TypePHP Docker 环境

基于 [swoole/typephp](https://github.com/swoole/typephp) v0.9.4 的 Linux 编译环境。编译自己的程序看[快速开始](#快速开始)；链接方式看[高级](#高级)；一条命令编译 hello、Laravel 或 Webman 看[一键编译](#一键编译)；改镜像、跟随上游发版看[开发](#开发)。

发布镜像：`ghcr.io/roiwk/typephp-docker`。日常使用钉标签 `0.9.4`。

## 快速开始

拉取镜像。仓库里的包若仍是私有的，先 `docker login ghcr.io`（用户名是 GitHub 用户名，密码是带 `read:packages` 的 Personal Access Token）。把[这个容器包](https://github.com/roiwk/typephp-docker/pkgs/container/typephp-docker)设为 Public 之后可以免登录拉取。

```bash
docker pull ghcr.io/roiwk/typephp-docker:0.9.4
```

二进制模式要求源码里有 `main(): void`。在项目目录中：

```bash
cat > hello.php << 'EOF'
<?php

function main(): void
{
    echo "Hello World!\n";
}
EOF

docker run --rm -v "$PWD":/src -w /src ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php
docker run --rm -v "$PWD":/src -w /src ghcr.io/roiwk/typephp-docker:0.9.4 ./hello
```

`tpc` 把可执行文件写到源码同目录，名字取输入文件的主文件名，所以上面生成 `./hello`。这是默认的动态链接：产物离开容器后还要带上镜像里的 `libphp.so` 和 `libphpx.so`。

容器以 root 编译。`tpc`、`tpc-static`、`tpc-private` 结束时会把工作目录里新建的 root 文件交回该目录的属主（也可用 `HOST_UID`、`HOST_GID` 指定）。二进制和编译中途写出的文件因此可以直接由宿主机用户改写。

用仓库里的 `docker-compose.yml` 时，源码目录用 `SRC`（默认当前目录）：

```bash
docker compose run --rm typephp tpc hello.php
```



## 高级



### 镜像里有什么

- PHP **8.4.26 ZTS**：CLI、头文件、`php-config`、Embed SAPI（`/opt/php/lib/libphp.so`）。已编入 bcmath、curl、ffi、gmp、mbstring、opcache、openssl、pcntl、pdo_sqlite、readline、sockets、sodium、sqlite3、zip、zlib，以及 [swoole/phpy](https://github.com/swoole/phpy)
- 与该发布包对应的 [swoole/phpx](https://github.com/swoole/phpx)（`PHPX_HOME=/opt/phpx`）
- 官方自举编译器 `tpc`（`tpc_v0.9.4_linux_*_php8.4.26-zts`）
- GCC、Clang、CMake 3.24+、Composer 2、GMP、MPFR、Python 3
- PHPX full-static SDK（`/opt/phpx/full-static/sdk`）。动态链接用镜像 PHP 8.4.26；SDK 里的 `libphp.a` 是 PHP **8.4.25**

`PHP_HOME`、`PHPX_HOME` 已写入环境变量。`libphp.so` 与 `libphpx.so` 已加入动态链接器路径。工作目录是 `/src`。

### 标签


| 标签                | 以后的发布会怎样                                          | 含义                          |
| ----------------- | ------------------------------------------------- | --------------------------- |
| `0.9.4-<提交号>`    | 每次构建新增一个，旧的提交号标签留在当时的镜像上                          | 这一次 git 提交。要钉死某次脚本改动时用它      |
| `0.9.4`           | 每次发布都改指向这次构建                                        | 这次 TypePHP 发布的最新镜像。日常使用钉这个   |
| `0.9.4-php8.4.26` | 每次发布都改指向这次构建                                        | TypePHP 与动态链接所用 PHP 补丁版本都钉死 |
| `0.9`             | 0.9.x 有新补丁时指向新镜像；升到 0.10 后停住                      | 当前 0.9 线上的最新补丁              |
| `php8.4`          | 仍使用 PHP 8.4 的新发布会指向新镜像；上游改用 8.5 后停住，同时出现 `php8.5` | 动态 PHP 小版本是 8.4 的最新镜像       |
| `latest`          | 每次发布都指向刚推上去的那一版                                   | 仓库里当前的 `versions.env`       |


以前的 `8.4` 不再更新。它如果已经存在，就停在最后一次用旧规则推上去的镜像。

### 三种链接


| `TYPEPHP_LINK`              | 直接调用                    | 产物                                                                                                                  |
| --------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `shared`（默认）                | `tpc hello.php`         | 动态链接镜像里的 `libphp.so`、`libphpx.so`                                                                                   |
| `static`（别名 `full-static`）  | `tpc-static hello.php`  | 未设置扩展变量：`--full-static`，链接 PHPX SDK，单个静态 ELF，常见 x86_64 Linux 上可直接运行。设置了扩展变量（含空名单）：扩展静态编进私有 PHP                      |
| `php-builder`（别名 `private`） | `tpc-private hello.php` | 现场编译一份私有静态 Embed PHP，补丁与镜像 PHP 8.4.26 相同。产物不需要 `libphp.so`，仍动态链接 libstdc++、GMP、OpenSSL。php-src 缓存在 `/root/.typephp` |


入口看到第一个词是 `tpc`，或第一个词以 `-` 开头，就按 `TYPEPHP_LINK` 转发。`tpc-static`、`tpc-private`、`php`、`composer`、`bash` 按命令本身执行。没有参数时执行 `tpc --version`。找不到命令时打印用法并退出 127。

镜像 PHP、`tpc` 和 full-static SDK 是 ZTS，这两条路径不读 `TYPEPHP_ZTS`。私有 PHP 默认 `zts: off`。多线程进入同一份 PHP 时再设 `TYPEPHP_ZTS=on`。

```bash
docker run --rm -e TYPEPHP_LINK=static -v "$PWD":/src -w /src \
  ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php
```

完全静态只用 SDK，编译器是 `/usr/bin/clang`，必须写成 `--compiler=/usr/bin/clang`。仓库里的等价命令是 `scripts/compile.sh static hello.php`。

### 扩展

三种链接都读 `TYPEPHP_EXTENSIONS`，逗号分隔，忽略空格，不区分大小写。


| 取值                                      | `shared`                                                                     | `static` / `php-builder`                                       |
| --------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------- |
| 未设置。Compose 在宿主未设置时传入 `__omit__`，与未设置相同 | 只用镜像里已有的 PHP                                                                 | `static` 走 full-static SDK。`php-builder` 编一份扩展名单为 `[]` 的私有 PHP |
| 空字符串、`none`、`base`、`minimal`、`-`、`[]`   | 不追加 `.so`                                                                    | 私有 PHP，名单 `[]`，不用 SDK                                          |
| `redis,gd` 这种名字                         | 编成 `.so`，写入镜像 PHP 的 `conf.d`，`tpc` 和 `php` 都会加载。缓存在 `/var/cache/typephp-ext` | 先装开发库，再由 `tpc` 静态编进私有 PHP。OpenSSL、GMP、libstdc++ 仍动态链接          |


镜像里已经编进 PHP 的扩展不用再写。可以点名的扩展：bz2、exif、ftp、gd、gettext、imagick、intl、mongodb、pcntl、pdo_pgsql、pgsql、posix、redis、soap、swoole、xsl、yaml。mysqli、pdo_mysql 只编进私有 PHP，用 `TYPEPHP_LINK=static` 或 `php-builder`。pcntl、posix 来自 php-src，没有额外系统库。PECL 版本钉死为 redis 6.3.0、swoole 6.2.3、yaml 2.3.0、mongodb 2.5.4、imagick 3.8.1。

私有 PHP 的下载版本是 `--php-version=8.4`，`tpc` 因此取和当前二进制相同的补丁 8.4.26。命令行若再写 `--php-version`，只接受 `8.4`。名单即使是 `[]`，程序源码里实际引用的扩展仍会被 `tpc` 自动收进这份私有 PHP。第一次编译要下载 php-src 并编译 PHP，耗时较长；缓存放在 `/root/.typephp`。

```bash
docker run --rm \
  -e TYPEPHP_EXTENSIONS=redis,swoole,gd \
  -v "$PWD":/src -w /src \
  -v typephp-ext:/var/cache/typephp-ext \
  ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php

docker run --rm \
  -e TYPEPHP_LINK=static \
  -e TYPEPHP_EXTENSIONS= \
  -v "$PWD":/src -w /src \
  -v typephp-php:/root/.typephp \
  ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php

docker run --rm \
  -e TYPEPHP_LINK=static \
  -e TYPEPHP_EXTENSIONS=redis,swoole,gd \
  -v "$PWD":/src -w /src \
  -v typephp-php:/root/.typephp \
  ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php
```

`docker run --rm` 时自己挂上这两个卷，扩展和私有 PHP 才不用每次重编。Compose 已经挂了 `typephp-ext` 和 `typephp-php`。

### 一键编译

[`scripts/compile.sh`](scripts/compile.sh) 把项目挂到宿主机绝对路径再编译，这样二进制里的 `__DIR__` 在宿主机上打得开。默认镜像是 `typephp:latest`。发布镜像用 `TYPEPHP_IMAGE=ghcr.io/roiwk/typephp-docker:0.9.4`。


| 命令                                                             | 产物                                                   |
| -------------------------------------------------------------- | ---------------------------------------------------- |
| `scripts/compile.sh shared hello.php`                          | 动态链接 `libphp.so`，生成 `./hello`                        |
| `scripts/compile.sh static hello.php`                          | 完全静态 SDK，单个 ELF，宿主机可直接运行。此时不要设置 `TYPEPHP_EXTENSIONS` |
| `TYPEPHP_EXTENSIONS=redis scripts/compile.sh static hello.php` | 静态，redis 编进私有 PHP，`zts` 默认 off                       |
| `scripts/compile.sh php-builder hello.php`                     | 私有 PHP，`zts` 默认 off                                  |
| `scripts/compile.sh laravel-cli /path/to/laravel`              | `build/laravel`，按 YAML 的 php-builder                 |
| `scripts/compile.sh laravel-fpm /path/to/laravel`              | `build/laravel-fpm`                                  |
| `scripts/compile.sh laravel-release /path/to/laravel`          | FPM 发布包，`build/laravel-fpm`                            |
| `scripts/compile.sh laravel-cli-release /path/to/laravel`      | artisan 发布包，`build/laravel`                          |
| `scripts/compile.sh webman /path/to/webman`                    | `build/webman`                                       |
| `scripts/compile.sh webman-release /path/to/webman`            | 同上，并打包 vendor、config、support                         |
| `scripts/compile.sh project /path/to/app`                      | 编译该目录已有的 `project.yml`，保留其中的 `sapi`               |
| `TYPEPHP_EXTENSIONS=redis,gd scripts/compile.sh webman /path`  | 把扩展写入项目 YAML 的 `php-builder.extensions` 再编译         |


示例 YAML 只在项目里还没有同名文件时复制。`TYPEPHP_EXTENSIONS` 会改写已有的 `php-builder.extensions`。没有 `vendor` 时先 `composer install --no-dev`。Laravel 若还没有 `artisan.php`，脚本会生成它来加载 `artisan`。FPM 示例配置是 [`examples/frameworks/laravel/php-fpm.conf`](examples/frameworks/laravel/php-fpm.conf)，编译 `laravel-fpm` 时若项目里还没有该文件会复制一份。同一轮还会写入 `typephp-fpm.php` 并放进 `embedded-files`，否则 FPM 链接缺少 `typephp_opcache_load`。Webman 编译会改 `config/app.php`，让日志和 pid 写到二进制所在目录下的 `runtime`。Laravel 编译会改 `bootstrap/app.php`，让日志、缓存、session 和上传写到二进制所在目录下的 `storage`。`cli` / `fpm` 走 YAML 里的私有静态 PHP。第一次会编译这份 PHP，缓存在卷 `typephp-php`。

```bash
scripts/compile.sh static hello.php
scripts/compile.sh laravel-cli /path/to/laravel && /path/to/laravel/build/laravel about
scripts/compile.sh webman /path/to/webman && /path/to/webman/build/webman start
```

`sources` 和 `ignore` 见 [docs/frameworks.md](docs/frameworks.md)。仓库样例：`tests/compile-frameworks.sh`，可再加 `laravel` 或 `webman`。

### 环境变量

命令行里已经写了的 `--php-builder`、`--php-version`、`--sapi`、`--full-static`、`--compiler`、`-j`、`--job` 保持原样，同名环境变量只补上没写的那些。


| 变量                   | 默认                                   | 作用                                                                                                                                                                                 |
| -------------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TYPEPHP_LINK`       | `shared`                             | `shared`：动态链接。`static` 或 `full-static`：未设置扩展变量时 `--full-static`；设置了（含空名单）则改为私有 PHP。`php-builder` 或 `private`：始终编私有静态 Embed PHP。其他值退出 2                                             |
| `TYPEPHP_EXTENSIONS` | 未设置                                  | 逗号分隔的扩展名。未设置时 `static` 用 SDK。空字符串、`none`、`base`、`minimal`、`-`、`[]` 表示只要最基础的 PHP：`shared` 不追加 `.so`，`static` 与 `php-builder` 使用 `extensions: []`。Compose 在宿主未设置时传入 `__omit__`，等同未设置 |
| `TYPEPHP_JOBS`       | 镜像未设置；Compose 为 `2`                  | 传给 `tpc` 的 `--job`。未设置时不追加。命令行已有 `-j` 或 `--job` 时保持命令行的值                                                                                                                           |
| `TYPEPHP_ZTS`        | `off`                                | 私有 PHP 的 `zts`。`php-builder`，以及设置了 `TYPEPHP_EXTENSIONS` 的 `static`（含空名单）会用到。`on` 只在程序从多个系统线程进入同一份 PHP 时需要。镜像 PHP 和 full-static SDK 仍是官方 ZTS 构建，不受这个变量影响                            |
| `TYPEPHP_SAPI`       | `embed`                              | 私有 PHP 的 `--sapi`。命令行已有 `--sapi` 时保持命令行的值                                                                                                                                          |
| `TYPEPHP_COMPILER`   | `/usr/bin/clang`                     | 仅完全静态 SDK 路径的 `--compiler=<路径>`。私有 PHP 不读它                                                                                                                                         |
| `TYPEPHP_EXT_CACHE`  | `/var/cache/typephp-ext`             | 动态扩展 `.so` 的缓存目录。Compose 卷名 `typephp-ext`                                                                                                                                          |
| `PHP_HOME`           | `/opt/php`                           | 镜像 PHP。镜像已设置                                                                                                                                                                       |
| `PHPX_HOME`          | `/opt/phpx`                          | PHPX 与 full-static SDK 的根目录。镜像已设置                                                                                                                                                  |
| `TYPEPHP_IMAGE`      | `ghcr.io/roiwk/typephp-docker:0.9.4` | 仅 Compose：要运行的镜像。本机构建用 `typephp:latest`                                                                                                                                            |
| `TYPEPHP_PULL`       | `missing`                            | 仅 Compose：本地没有该镜像时才拉取                                                                                                                                                              |
| `SRC`                | `.`                                  | 仅 Compose：挂到容器 `/src` 的宿主目录                                                                                                                                                        |


Compose 示例：

```bash
TYPEPHP_LINK=static \
TYPEPHP_EXTENSIONS=none \
SRC=/path/to/project \
docker compose run --rm typephp tpc hello.php
```



## 开发

这一节面向维护 [roiwk/typephp-docker](https://github.com/roiwk/typephp-docker) 的人。

### 仓库里有什么


| 路径                                                                                                                    | 作用                                                        |
| --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `Dockerfile`                                                                                                          | 从 Ubuntu 24.04 编译 PHP、PHPX、phpy，再装入 `tpc`、Clang 和静态 SDK   |
| `versions.env`                                                                                                        | 唯一的版本钉。TypePHP、PHP、PHPX 提交、phpy 提交、静态 SDK 和校验和都在这里        |
| `scripts/build-php.sh`、`build-phpx.sh`、`build-phpy.sh`                                                                | 镜像构建时调用的编译脚本                                              |
| `scripts/install-tpc.sh`、`install-static-sdk.sh`                                                                      | 下载官方 `tpc` 包和 PHPX full-static SDK，并校验 SHA256             |
| `scripts/tpc-static.sh`、`tpc-private.sh`、`entrypoint.sh`、`enable-extensions.sh`、`extension-mode.sh`、`chown-output.sh` | 使用时的链接方式、按需扩展、空名单判断，以及把 root 新建文件交回项目属主                   |
| `scripts/compile.sh`                                                                                                  | 一键编译：`shared`、`static`、`php-builder`、`laravel-*`、`webman` |
| `scripts/compile-hostpath.sh`                                                                                         | 被 `compile.sh` 调用：按宿主机绝对路径挂载后再跑 `tpc`                     |
| `scripts/smoke-test.sh`                                                                                               | 构建末尾编译并运行一段 Hello World，确认动态链接可用                          |
| `scripts/build-image.sh`                                                                                              | 读取 `versions.env`，在本机 `docker build`                      |
| `scripts/sync-release.sh`                                                                                             | 按 GitHub 发布信息重写 `versions.env`                            |
| `scripts/publish-image.sh`                                                                                            | 把本机已经构建好的镜像打上仓库标签并推送，不再编译                                 |
| `.github/workflows/publish-image.yml`                                                                                 | 在 GitHub Actions 里构建并推送到 GHCR                             |
| `.github/workflows/check-typephp.yml`                                                                                 | 每 3 天看一次 TypePHP 的 latest；有更新就改 `versions.env` 并触发上面的发布   |




### 本地构建

```bash
MAKE_JOBS=2 scripts/build-image.sh
```

脚本按文首标签规则打本地标签，例如 `typephp:0.9.4`、`typephp:php8.4`、`typephp:latest`。内存紧时把 `MAKE_JOBS` 保持在 2。首次构建要编译 PHP、PHPX 和 phpy，大约几十分钟，结束前跑 `scripts/smoke-test.sh`。

Dockerfile 前半段是 apt、PHP、PHPX、phpy，改这些层会使编译缓存失效。Clang、静态 SDK 和入口脚本在后面的层，改它们不会重编 PHP。本机构建完成后把镜像名换成 `typephp:latest`，用法与发布镜像相同。

### 版本必须一起换

`versions.env` 里这几项绑在同一次 TypePHP 发布上：

- `tpc` 发布包文件名里的 PHP 补丁版本就是动态链接用的 `PHP_VERSION`。它和 `libphp.so` 的 ZTS ABI 绑在一起，`tpc` 进程自己也要加载这份库。
- `PHPX_REF`、`PHPY_REF` 取该 TypePHP 发布时，[swoole/phpx](https://github.com/swoole/phpx) 和 [swoole/phpy](https://github.com/swoole/phpy) 的 `master` 上的提交。`tpc` 启动要加载当时的 `libphpx.so` 和 `phpy.so`。
- `PHPX_SDK_*` 取不晚于这次 TypePHP 发布的 PHPX Release 里的 `phpx-sdk_*_linux-*.tar.xz`。`--full-static` 用这份静态库，PHP 补丁可以和动态运行时不同。当前动态运行时是 8.4.26，静态库是 8.4.25。

`scripts/sync-release.sh` 按这个规则填写校验和与提交号。

### 升级 TypePHP

```bash
scripts/sync-release.sh v0.9.5
```

不带参数时跟踪 GitHub 上的 latest，并重写整个 `versions.env`。生成后看一眼 `PHP_VERSION`、`PHPX_REF`、`PHPY_REF`、`PHPX_SDK_VERSION`，再 `MAKE_JOBS=2 scripts/build-image.sh`。

若完全静态链接报 SDK 或 musl 启动文件 `crt1.o` 缺失，把 `PHPX_SDK_VERSION` 改成与这次 `tpc` 同时期、且压缩包里带 `lib/musl/crt1.o` 的 PHPX Release，然后重新构建。

`.github/workflows/check-typephp.yml` 也会做这件事。它在每月 1、4、7、10、13、16、19、22、25、28 日的 02:00 UTC 运行，也可以在 Actions 页面手动运行 “Check TypePHP release”。GitHub 的定时语法写不出严格的每 72 小时，所以用每 3 个日号一次。

发现 [swoole/typephp](https://github.com/swoole/typephp) 的 latest 比 `versions.env` 新时，工作流用 `TYPEPHP_PHP_MINOR=auto` 调用 `scripts/sync-release.sh`：在这次发布包里选择最高的 PHP 小版本（8.4 和 8.5 同时存在时选 8.5），写回 `versions.env` 并推到 `main`，再触发 “Publish image”。版本相同，或本仓库钉的版本比 latest 还新时，不改文件、也不构建。用 `GITHUB_TOKEN` 推上去的提交不会再次触发 `push` 工作流，所以发布是单独调度的。

### 发布到 GHCR

推到 `main`，并且改动了 `Dockerfile`、`versions.env`、`scripts/` 或 `.github/workflows/publish-image.yml` 时，Actions 会构建并推送。也可以在 Actions 页面手动运行 “Publish image”。

工作流把镜像名设为 `ghcr.io/roiwk/typephp-docker`。一次成功的发布会先推一个新标签 `0.9.4-<12 位提交号>`，再把 `0.9.4`、`0.9.4-php8.4.26`、`0.9`、`php8.4`、`latest` 指到同一份镜像。GHCR 上同名标签看起来还在，指向的是这次构建。TypePHP 升到 0.9.5 且 PHP 仍是 8.4 时，`0.9.4` 和带提交号的旧标签留在旧镜像，`0.9`、`php8.4`、`latest` 改指向新镜像。上游改用 PHP 8.5 时，`php8.4` 停在最后一版 8.4 镜像，新发布另打 `php8.5`。

本机已经有构建结果时，登录后直接推这份镜像。密码是带 `write:packages` 的 GitHub token；用 Actions 发布时 `GITHUB_TOKEN` 已具备这个权限。

```bash
docker login ghcr.io
scripts/publish-image.sh ghcr.io/roiwk/typephp-docker
```

GitHub 第一次创建的容器包默认是私有的。打开包设置，把 `typephp-docker` 设为 Public，其他人才能免登录拉取。