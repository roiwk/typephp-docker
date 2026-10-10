# 框架项目的 project.yml

多文件项目用 YAML 管理编译参数。字段说明见 [project.yml 配置](https://www.swoole.com/aot/zh/docs/project-yml)。命令行参数优先于 YAML，YAML 优先于默认值。

示例 YAML 在 [`examples/frameworks/`](../examples/frameworks/)。用 [`scripts/compile.sh`](../scripts/compile.sh) 编译时，脚本会把对应文件拷进项目根目录。路径都相对这份 YAML 所在目录。


| 框架      | 开发配置                  | 命令行                       | 发布配置                          |
| ------- | --------------------- | ------------------------- | ----------------------------- |
| Laravel | `laravel/project.yml` | `laravel/project-cli.yml` | `laravel/project-release.yml` |
| Webman  | `webman/project.yml`  | 与开发配置相同，入口是 `start.php`   | `webman/project-release.yml`  |


## 这些配置在做什么

`mode` 是产物类型。`sapi` 是 `bin` 可执行文件里的 PHP 进程接口。`cli` 和 `fpm` 必须配合 `php-builder`，由编译器从 php-src 做一份私有 PHP，扩展静态编进这份 PHP。


| 跑法                 | YAML                         | 入口                                                                         |
| ------------------ | ---------------------------- | -------------------------------------------------------------------------- |
| 网页，自带 PHP-FPM      | `sapi: fpm`                  | 不写 `entry`。站点脚本仍是框架原来的 `public/index.php` 或 `web/index.php`，在 FPM pool 里配置 |
| 命令行、Webman         | `sapi: cli` 且 `entry` 指向启动脚本 | `entry` 由 Zend 执行，可以有顶层代码。即使它也出现在 `sources` 里，编译器也会把它移出 AOT                |
| 已有 php-fpm，只编译业务代码 | `mode: ext`                  | 得到 `.so`。这种模式不能写 `sapi`、`php-builder`、`embedded-files`                     |


`embed` 是默认 SAPI，要求源码里有 `main()`。框架自带的启动脚本没有这个函数，所以示例用 `fpm` 或 `cli`。

`php-version` 是 `"8.4"`。`php-builder.zts` 是 `off`。镜像 PHP 和 full-static SDK 仍是 ZTS。`job: 2`。

## 哪些代码放进 sources

官方建议：`vendor` 里的框架和类库继续用 Composer Autoload，不要整包编译。需要加速的目录再用白名单写进 `sources`。某个文件无法静态编译时，把它写进 `ignore`。`ignore` 只接受明确路径，不支持通配符；目录会递归排除；路径不存在就跳过。

类的继承链必须全部是静态编译类。控制器继承了框架基类时，只编译 `app`、不编译那个基类，编译会失败。处理办法有两种：

- 这些类留在 Composer 里，`sources` 只放不继承框架类的目录。
- 把基类所在包一并写入 `sources`，再把编译失败的文件写入 `ignore`。

`bootstrap`、`routes`、`config`、Webman 的 `start.php` 含有顶层执行代码。AOT 源码的全局作用域只能放声明，所以它们要么作为 `entry`，要么留在 `embedded-files` 或磁盘上，不要放进 `sources`。

`__DIR__` 记的是编译时的路径。`scripts/compile.sh` 把项目挂到宿主机同一路径，二进制才能在宿主机上打开这些文件。

## 编译

在仓库里执行。第二个参数是项目根目录，省略则用当前目录。

| 命令 | 链接 | 产物 |
|---|---|---|
| `scripts/compile.sh static hello.php` | full-static SDK，单个 ELF | `./hello` |
| `TYPEPHP_EXTENSIONS=redis scripts/compile.sh static hello.php` | 扩展编进私有 PHP，`zts` 默认 off | `./hello` |
| `scripts/compile.sh shared hello.php` | 动态链接 `libphp.so` | `./hello` |
| `scripts/compile.sh laravel-cli /path/to/laravel` | YAML 的 php-builder，`zts: off` | `build/laravel` |
| `scripts/compile.sh laravel-fpm /path/to/laravel` | 同上 | `build/laravel-fpm` |
| `scripts/compile.sh laravel-release /path/to/laravel` | 同上，并打包 vendor | `build/laravel-fpm` |
| `scripts/compile.sh laravel-cli-release /path/to/laravel` | 打包 artisan | `build/laravel` |
| `scripts/compile.sh webman /path/to/webman` | YAML 的 php-builder，`zts: off` | `build/webman` |
| `scripts/compile.sh webman-release /path/to/webman` | 同上，并打包 vendor、config、support | `build/webman` |
| `scripts/compile.sh project /path/to/app project.yml` | 使用项目里已有的 YAML，保留 `sapi` | YAML 的 `output` |
| `TYPEPHP_EXTENSIONS=redis,gd scripts/compile.sh laravel-cli /path` | 写入 `php-builder.extensions` 后再编译 | `build/laravel` |

`static` 在未设置 `TYPEPHP_EXTENSIONS` 时用 SDK。含 `sapi: cli`、`sapi: fpm` 或 `php-builder` 的 YAML 用 `project`，脚本不会把它改成 Embed。示例 YAML 只在项目里缺少同名文件时复制。`TYPEPHP_EXTENSIONS=redis,gd` 会改写 `php-builder.extensions`；空字符串、`none`、`[]` 写成空名单。

没有 `vendor` 时脚本会执行 `composer install --no-dev`。第一次框架编译会下载并编译这份 PHP，缓存在卷 `typephp-php`。编译结束时，新建的 root 文件交回项目属主。

`laravel-release` 打包 FPM。`laravel-cli-release` 打包 artisan。发布配置只追加 `embedded-files` 和 `optimize: 2`。日志、缓存、上传不要打进去。

```bash
scripts/compile.sh static hello.php
scripts/compile.sh laravel-cli /path/to/laravel
./build/laravel about
scripts/compile.sh webman /path/to/webman
./build/webman start
```

## Laravel

`laravel-fpm` 的请求脚本仍是 `public/index.php`。池配置是 [`examples/frameworks/laravel/php-fpm.conf`](../examples/frameworks/laravel/php-fpm.conf)，编译时若项目根目录没有 `php-fpm.conf` 会复制一份：`./build/laravel-fpm --fpm-config php-fpm.conf`。`laravel-cli` 的参数传给 `artisan.php`，例如 `./build/laravel migrate --force`。`sources` 是 `app`。`app/Models` 和 `app/Providers` 继承 Illuminate，写在 `ignore` 里。

`scripts/compile.sh` 会改 `bootstrap/app.php`：编译出的二进制把日志、缓存、session 和上传写到自己所在目录下的 `storage`，二进制放在哪个目录都一样。`php artisan` 仍用项目根的 `storage`。已经改过的配置会保留。

FPM 的中间文件在 `build/fpm`，artisan 的在 `build/cli`。两套编译各用一份 `build-dir`。FPM 没有入口脚本，`scripts/compile.sh` 会写入 `typephp-fpm.php` 并放进 `embedded-files`，否则链接缺少 `typephp_opcache_load`。`project-cli.yml` 用空的 `embedded-files` 盖掉这一项。

## Webman

`./build/webman start`、`stop`、`status`。`config` 和 `support` 保持普通 PHP。`app/process`、`app/model`、`app/middleware` 继承 Workerman，写在 `ignore` 里。

`scripts/compile.sh` 会改 `config/app.php` 的 `runtime_path`：编译出的二进制把日志、pid 写到自己所在目录下的 `runtime`，二进制放在哪个目录都一样。`php start.php` 仍用项目根的 `runtime`。已经改过的配置会保留。

## 其他框架

Symfony 与 Laravel 同一形状：网页用 `sapi: fpm`，请求脚本是 `public/index.php`；控制台把 `entry` 设为 `bin/console`。Workerman 与 Webman 同一形状，`entry` 设为它的启动脚本。

## 编译检查

`tests/compile-frameworks.sh` 编译仓库里的 Laravel（`about`）和 Webman（请求 `8787`）。产物在 `tests/frameworks/<框架>/build`，日志是同目录的 `compile.log`。

```bash
tests/compile-frameworks.sh
tests/compile-frameworks.sh laravel
tests/compile-frameworks.sh webman
```
