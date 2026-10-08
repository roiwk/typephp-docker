# TypePHP Docker 环境

基于 [swoole/typephp](https://github.com/swoole/typephp) v0.9.4 的 Linux 编译环境。镜像里已经装好：

- PHP **8.4.26 ZTS**，带 CLI、头文件、`php-config` 和 Embed SAPI（`/opt/php/lib/libphp.so`）
- 与该发布包对应的 [swoole/phpx](https://github.com/swoole/phpx)（`PHPX_HOME=/opt/phpx`）
- 官方自举编译器 `tpc`（`tpc_v0.9.4_linux_*_php8.4.26-zts`）
- [swoole/phpy](https://github.com/swoole/phpy)，`tpc` 启动时依赖这个扩展
- GCC、Clang、CMake 3.24+、Composer 2、GMP、MPFR、Python 3
- PHPX full-static SDK（`/opt/phpx/full-static/sdk`，当前 PHP 8.4.25 的 `libphp.a`）

`PHP_HOME` 和 `PHPX_HOME` 已写入环境变量，`libphp.so` 与 `libphpx.so` 已加入动态链接器路径。

## 使用

镜像在发布时编译一次 PHP、PHPX 和 phpy。使用时拉取即可，不用在每台机器上 `docker build`。

```bash
docker pull ghcr.io/<owner>/typephp:8.4

docker run --rm -v "$PWD":/src -w /src ghcr.io/<owner>/typephp:8.4 tpc hello.php
```

本机已经构建过的镜像名是 `typephp:8.4`，把上面的镜像名换成它即可。Compose 默认也用这个本地名；要用仓库里的镜像时：

```bash
TYPEPHP_IMAGE=ghcr.io/<owner>/typephp:8.4 docker compose run --rm typephp tpc hello.php
```

在项目目录中：

```bash
cat > hello.php << 'EOF'
<?php

function main(): void
{
    echo "Hello World!\n";
}
EOF

docker run --rm -v "$PWD":/src -w /src typephp:8.4 tpc hello.php
docker run --rm -v "$PWD":/src -w /src typephp:8.4 ./hello
```

也可以用 Compose，把源码目录指到 `SRC`：

```bash
SRC=/path/to/project docker compose run --rm typephp tpc hello.php
```

容器以 root 运行。挂载目录里生成的文件属主会是 root，需要时在宿主机执行 `sudo chown -R "$USER:" .`。

二进制模式要求源码里有 `main(): void`。默认编译结果会链接本镜像中的 `libphp.so` 和 `libphpx.so`，拿到容器外运行时需要自带这两份库。

## 静态编译

`tpc` 有两种不依赖宿主机 `libphp.so` 的链接方式：

| `TYPEPHP_LINK` | 命令 | 产物 |
|---|---|---|
| `shared`（默认） | `tpc hello.php` | 动态链接镜像里的 `libphp.so`、`libphpx.so` |
| `static` | `tpc-static hello.php` | `--full-static`，链接 PHPX SDK 里的 `libphp.a`、`libphpx.a` 和 musl，得到单个可执行文件 |
| `php-builder` | `tpc-private hello.php` | 现场编译一份私有静态 Embed PHP。产物不再需要 `libphp.so`，但仍动态链接 GMP、OpenSSL 等系统库。第一次会下载 php-src，缓存在 `/root/.typephp` |

完全静态链接使用 Clang，以及 PHPX 发布的 SDK（当前是 PHP **8.4.25** 的 `libphp.a`，和镜像里动态用的 PHP 8.4.26 不是同一份）。

```bash
docker run --rm -v "$PWD":/src -w /src typephp:8.4 tpc-static hello.php
# 或者
docker run --rm -e TYPEPHP_LINK=static -v "$PWD":/src -w /src typephp:8.4 tpc hello.php
```

`php-builder` 还可以用环境变量加扩展：`TYPEPHP_EXTENSIONS=swoole,mongodb`、`TYPEPHP_ZTS=on`、`TYPEPHP_SAPI=embed`。

## 跟着 TypePHP 升级

版本都写在 `versions.env`。官方 `tpc` 包、动态 `libphp.so`、PHPX、phpy、静态 SDK 必须一起换，不能只改其中一个：

- `tpc` 发布包文件名里的 PHP 补丁版本，就是动态链接用的 `PHP_VERSION`。它和 `libphp.so` 的 ZTS ABI 绑在一起。
- `PHPX_REF`、`PHPY_REF` 取该 TypePHP 发布时两个仓库 `master` 上的提交。`tpc` 进程本身要加载当时的 `libphpx.so` 和 `phpy.so`。
- `PHPX_SDK_*` 取不晚于这次 TypePHP 发布的 PHPX Release 里的 `phpx-sdk_*_linux-*.tar.xz`。`--full-static` 用的是这份静态库，PHP 小版本可以和动态运行时差一个补丁。

```bash
scripts/sync-release.sh v0.9.5
```

`sync-release.sh` 不带参数时跟踪 GitHub 上的 latest，并重写 `versions.env`。把仓库推到 GitHub 的 `main` 后，`.github/workflows/publish-image.yml` 会构建并推到 `ghcr.io/<owner>/<repo>`，标签是 `8.4`、`0.9.4` 和 `0.9.4-php8.4.26`。使用者再 `docker pull` 新标签。

本机已经有 `typephp:8.4`、不想再编译一遍时，登录仓库后直接推这份镜像：

```bash
docker login ghcr.io
scripts/publish-image.sh ghcr.io/<owner>/typephp
```

第一次推上去的包默认是私有的。到 GitHub Packages 把这个容器设为 Public 之后，其他人才能免登录拉取。

若静态链接报 SDK 或 musl 启动文件缺失，说明这份编译器要的 SDK 布局变了，把 `PHPX_SDK_VERSION` 改成与这次 `tpc` 同时期的 PHPX Release 后重新发布。维护者在本机重新编译用 `scripts/build-image.sh`（内存紧时保持 `MAKE_JOBS=2`）。
