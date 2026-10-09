# TypePHP Docker 环境

基于 [swoole/typephp](https://github.com/swoole/typephp) v0.9.4 的 Linux 编译环境。编译 PHP 程序时拉取镜像即可；维护镜像、跟随上游升级时再看文末的开发部分。

发布镜像：`ghcr.io/roiwk/typephp-docker`

| 标签 | 会不会被以后的发布改掉 | 含义 |
|---|---|---|
| `0.9.4` | 同一 TypePHP 版本重新构建时会更新 | 这次 TypePHP 发布。日常使用钉这个 |
| `0.9.4-php8.4.26` | 同一对版本重新构建时会更新 | TypePHP 与动态链接所用 PHP 补丁版本都钉死 |
| `0.9` | TypePHP 0.9.x 有新补丁时会指向新镜像；升到 0.10 后停住 | 当前 0.9 线上的最新补丁 |
| `php8.4` | 仍使用 PHP 8.4 的新 TypePHP 发布会指向新镜像；上游改用 PHP 8.5 后停住，同时出现 `php8.5` | 动态 PHP 小版本是 8.4 的最新镜像 |
| `latest` | 每次发布都指向刚推上去的那一版 | 仓库里当前的 `versions.env` |

以前的 `8.4` 不再更新。它如果已经存在，就停在最后一次用旧规则推上去的镜像。

镜像里已经装好：

- PHP **8.4.26 ZTS**，带 CLI、头文件、`php-config` 和 Embed SAPI（`/opt/php/lib/libphp.so`）
- 与该发布包对应的 [swoole/phpx](https://github.com/swoole/phpx)（`PHPX_HOME=/opt/phpx`）
- 官方自举编译器 `tpc`（`tpc_v0.9.4_linux_*_php8.4.26-zts`）
- [swoole/phpy](https://github.com/swoole/phpy)，`tpc` 启动时依赖这个扩展
- GCC、Clang、CMake 3.24+、Composer 2、GMP、MPFR、Python 3
- PHPX full-static SDK（`/opt/phpx/full-static/sdk`，当前 PHP 8.4.25 的 `libphp.a`）

`PHP_HOME` 和 `PHPX_HOME` 已写入环境变量，`libphp.so` 与 `libphpx.so` 已加入动态链接器路径。容器工作目录是 `/src`。入口脚本在第一个参数是 `tpc` 时读取 `TYPEPHP_LINK`；其他命令原样执行，例如 `bash`、`php`、`composer`。

## 使用

这一节面向编译自己的 TypePHP 程序。不需要克隆本仓库，也不需要在本机编译 PHP。

### 拉取

```bash
docker pull ghcr.io/roiwk/typephp-docker:0.9.4
```

仓库里的包若仍是私有的，先登录再拉取。用户名是 GitHub 用户名，密码是带 `read:packages` 权限的 Personal Access Token：

```bash
docker login ghcr.io
```

把 [这个容器包](https://github.com/roiwk/typephp-docker/pkgs/container/typephp-docker) 设为 Public 之后，可以免登录拉取。

### 编译并运行

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

`tpc` 默认把可执行文件写到源码同目录，名字取输入文件的主文件名。上面的例子会生成 `./hello`。

容器以 root 运行。挂载目录里生成的文件属主会是 root，需要时在宿主机执行：

```bash
sudo chown -R "$USER:" .
```

### 链接方式

| `TYPEPHP_LINK` | 命令 | 产物 |
|---|---|---|
| `shared`（默认） | `tpc hello.php` | 动态链接镜像里的 `libphp.so`、`libphpx.so` |
| `static` | `tpc-static hello.php` | `--full-static`，链接 PHPX SDK 里的 `libphp.a`、`libphpx.a` 和 musl，得到单个可执行文件 |
| `php-builder` | `tpc-private hello.php` | 现场编译一份私有静态 Embed PHP。产物不再需要 `libphp.so`，但仍动态链接 GMP、OpenSSL 等系统库。第一次会下载 php-src，缓存在容器内 `/root/.typephp` |

完全静态链接使用 Clang，以及 PHPX 发布的 SDK。当前 SDK 里的 `libphp.a` 是 PHP **8.4.25**，和镜像里动态用的 PHP 8.4.26 不是同一份。

```bash
# 完全静态，产物可以拿到容器外直接运行
docker run --rm -v "$PWD":/src -w /src ghcr.io/roiwk/typephp-docker:0.9.4 tpc-static hello.php

# 与上面等价：入口看到 tpc，再按 TYPEPHP_LINK 转给 tpc-static
docker run --rm -e TYPEPHP_LINK=static -v "$PWD":/src -w /src \
  ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php

# 私有 Embed。扩展名用逗号分隔，留空表示不额外启用扩展
docker run --rm \
  -e TYPEPHP_LINK=php-builder \
  -e TYPEPHP_EXTENSIONS=swoole,mongodb \
  -e TYPEPHP_ZTS=on \
  -e TYPEPHP_SAPI=embed \
  -v "$PWD":/src -w /src \
  ghcr.io/roiwk/typephp-docker:0.9.4 tpc hello.php
```

默认的动态链接产物离开容器后，还要自带镜像里的 `libphp.so` 和 `libphpx.so`。`tpc-static` 的产物是静态 ELF，在常见的 x86_64 Linux 上可以直接运行。`tpc-private` 的产物不再需要 `libphp.so`，运行时仍需要系统里的 GMP、OpenSSL 等库。

并行度用 `TYPEPHP_JOBS`（默认由 Compose 设为 2）。已经在命令行写了 `-j` 或 `--job` 时，环境变量不会再覆盖。完全静态时编译器默认是 `/usr/bin/clang`，可用 `TYPEPHP_COMPILER` 换成别的路径。

### Compose

`docker-compose.yml` 默认拉取 `ghcr.io/roiwk/typephp-docker:0.9.4`。本机刚构建的镜像用 `TYPEPHP_IMAGE=typephp:latest`。源码目录用 `SRC`，默认是当前目录。

```bash
TYPEPHP_IMAGE=ghcr.io/roiwk/typephp-docker:0.9.4 \
  docker compose run --rm typephp tpc hello.php

TYPEPHP_IMAGE=ghcr.io/roiwk/typephp-docker:0.9.4 \
  TYPEPHP_LINK=static \
  SRC=/path/to/project \
  docker compose run --rm typephp tpc hello.php
```

| 变量 | 默认 | 作用 |
|---|---|---|
| `TYPEPHP_IMAGE` | `ghcr.io/roiwk/typephp-docker:0.9.4` | Compose 使用的镜像 |
| `TYPEPHP_PULL` | `missing` | 本地没有该镜像时才拉取 |
| `SRC` | `.` | 挂载到容器 `/src` 的目录 |
| `TYPEPHP_LINK` | `shared` | `shared`、`static`、`php-builder` |
| `TYPEPHP_JOBS` | `2` | `tpc` 的并行编译任务数 |
| `TYPEPHP_ZTS` | `on` | 仅 `php-builder`：私有 PHP 是否启用 ZTS |
| `TYPEPHP_SAPI` | `embed` | 仅 `php-builder`：`--sapi` |
| `TYPEPHP_EXTENSIONS` | 空 | 仅 `php-builder`：逗号分隔的扩展名 |
| `TYPEPHP_COMPILER` | `/usr/bin/clang` | 仅完全静态：C++ 编译器 |

## 开发

这一节面向维护 [roiwk/typephp-docker](https://github.com/roiwk/typephp-docker) 的人：在本机改镜像、跟随 TypePHP 发版，以及把镜像推到 `ghcr.io/roiwk/typephp-docker`。

### 仓库里有什么

| 路径 | 作用 |
|---|---|
| `Dockerfile` | 从 Ubuntu 24.04 编译 PHP、PHPX、phpy，再装入 `tpc`、Clang 和静态 SDK |
| `versions.env` | 唯一的版本钉。TypePHP、PHP、PHPX 提交、phpy 提交、静态 SDK 和校验和都在这里 |
| `scripts/build-php.sh`、`build-phpx.sh`、`build-phpy.sh` | 镜像构建时调用的编译脚本 |
| `scripts/install-tpc.sh`、`install-static-sdk.sh` | 下载官方 `tpc` 包和 PHPX full-static SDK，并校验 SHA256 |
| `scripts/tpc-static.sh`、`tpc-private.sh`、`entrypoint.sh` | 使用时的链接方式入口 |
| `scripts/smoke-test.sh` | 构建末尾编译并运行一段 Hello World，确认动态链接可用 |
| `scripts/build-image.sh` | 读取 `versions.env`，在本机 `docker build` |
| `scripts/sync-release.sh` | 按 GitHub 发布信息重写 `versions.env` |
| `scripts/publish-image.sh` | 把本机已经构建好的镜像打上仓库标签并推送，不再编译 |
| `.github/workflows/publish-image.yml` | 在 GitHub Actions 里构建并推送到 GHCR |
| `.github/workflows/check-typephp.yml` | 每 3 天看一次 TypePHP 的 latest；有更新就改 `versions.env` 并触发上面的发布 |

### 本地构建

```bash
MAKE_JOBS=2 scripts/build-image.sh
```

脚本会按文首的规则打本地标签，例如 `typephp:0.9.4`、`typephp:php8.4` 和 `typephp:latest`。内存紧时把 `MAKE_JOBS` 保持在 2。首次构建要编译 PHP、PHPX 和 phpy，大约需要几十分钟。构建结束前会跑 `scripts/smoke-test.sh`。

Dockerfile 前半段是 apt、PHP、PHPX、phpy。改这些层会使编译缓存失效。Clang、静态 SDK 和 `tpc-static` 等脚本在后面的层，改它们不会重编 PHP。

本机构建完成后，使用方式和发布镜像相同，把镜像名换成 `typephp:latest`：

```bash
docker run --rm -v "$PWD":/src -w /src typephp:latest tpc hello.php
```

### 版本必须一起换

`versions.env` 里的这几项绑在同一次 TypePHP 发布上，不能只改其中一个：

- `tpc` 发布包文件名里的 PHP 补丁版本就是动态链接用的 `PHP_VERSION`。它和 `libphp.so` 的 ZTS ABI 绑在一起，`tpc` 进程自己也要加载这份库。
- `PHPX_REF`、`PHPY_REF` 取该 TypePHP 发布时，[swoole/phpx](https://github.com/swoole/phpx) 和 [swoole/phpy](https://github.com/swoole/phpy) 的 `master` 上的提交。`tpc` 启动要加载当时的 `libphpx.so` 和 `phpy.so`。
- `PHPX_SDK_*` 取不晚于这次 TypePHP 发布的 PHPX Release 里的 `phpx-sdk_*_linux-*.tar.xz`。`--full-static` 用的是这份静态库，PHP 补丁版本可以和动态运行时不同。当前动态运行时是 8.4.26，静态库是 8.4.25。

`scripts/sync-release.sh` 会按这个规则填写校验和与提交号。

### 升级 TypePHP

```bash
scripts/sync-release.sh v0.9.5
```

不带参数时跟踪 GitHub 上的 latest，并重写整个 `versions.env`。生成后看一眼 `PHP_VERSION`、`PHPX_REF`、`PHPY_REF` 和 `PHPX_SDK_VERSION`，再构建：

```bash
MAKE_JOBS=2 scripts/build-image.sh
```

若完全静态链接报 SDK 或 musl 启动文件 `crt1.o` 缺失，把 `PHPX_SDK_VERSION` 改成与这次 `tpc` 同时期、且压缩包里带 `lib/musl/crt1.o` 的 PHPX Release，然后重新构建。

`.github/workflows/check-typephp.yml` 也会做这件事。它在每月 1、4、7、10、13、16、19、22、25、28 日的 02:00 UTC 运行，也可以在 Actions 页面手动运行 “Check TypePHP release”。GitHub 的定时语法不能写成严格的每 72 小时，所以用的是每 3 个日号一次。

发现 [swoole/typephp](https://github.com/swoole/typephp) 的 latest 比 `versions.env` 新时，工作流用 `TYPEPHP_PHP_MINOR=auto` 调用 `scripts/sync-release.sh`：在这次发布包里选择最高的 PHP 小版本（8.4 和 8.5 同时存在时选 8.5），写回 `versions.env` 并推到 `main`，再触发 “Publish image”。版本相同，或本仓库钉的版本比 latest 还新时，不改文件、也不构建。用 `GITHUB_TOKEN` 推上去的提交不会再次触发 `push` 工作流，所以发布是单独调度的。

### 发布到 GHCR

推到 `main`，并且改动了 `Dockerfile`、`versions.env`、`scripts/` 或 `.github/workflows/publish-image.yml` 时，Actions 会构建并推送。也可以在 GitHub 的 Actions 页面手动运行 “Publish image”。

工作流把镜像名设为 `ghcr.io/roiwk/typephp-docker`（即 `ghcr.io/` 加上仓库 `roiwk/typephp-docker`）。一次成功的发布会推 `0.9.4`、`0.9.4-php8.4.26`、`0.9`、`php8.4` 和 `latest`。TypePHP 升到 0.9.5 且 PHP 仍是 8.4 时，`0.9.4` 留在旧镜像，`0.9`、`php8.4` 和 `latest` 改指向新镜像。上游改用 PHP 8.5 时，`php8.4` 停在最后一版 8.4 镜像，新发布另打 `php8.5`。

本机已经有构建结果、不想在 Actions 里再编译一遍时，登录后直接推这份镜像：

```bash
docker login ghcr.io
scripts/publish-image.sh ghcr.io/roiwk/typephp-docker
```

`docker login ghcr.io` 的密码同样是 GitHub token，推送需要 `write:packages`。用 Actions 发布时，`GITHUB_TOKEN` 已具备这个权限。

GitHub 第一次创建的容器包默认是私有的。打开包设置，把 `typephp-docker` 设为 Public，其他人才能按上一节免登录拉取。
