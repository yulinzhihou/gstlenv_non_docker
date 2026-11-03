# 运行环境优化（2026-11-03）

## 服务开机自启

安装结束前统一检查已安装的环境服务：MySQL、Nginx、PHP-FPM 和 Redis/Valkey。
systemd 系统执行 enable 后还会检查 is-enabled，失败时不显示完整安装成功。
SysV 系统使用 chkconfig 或 update-rc.d 注册启动项。

CentOS Stream 10 使用 Valkey 提供 Redis 兼容服务，检查命令为：

```bash
systemctl is-enabled mysqld nginx php-fpm valkey
systemctl status mysqld nginx php-fpm valkey --no-pager
source /root/.gs/.env
REDISCLI_AUTH="$REDIS_PASSWORD" valkey-cli ping
MYSQL_PWD="$TL_MYSQL_PASSWORD" mysql --no-defaults -uroot -e 'SELECT 1;'
```

未选择安装的可选服务不会强制安装或创建虚假的启动项。以上不包含游戏进程自动开服；
游戏仍由 `runtlbb` 管理。

## 凭据生成与恢复

首次安装独立生成五个 12 位随机值：MySQL root、游戏数据库账号、Redis/Valkey、
GM 登录密码及 GM 通信密钥。每个值包含大写字母、小写字母、数字及符号；
符号限定为 `_+=.-`，兼容游戏 INI、Shell、Redis、YAML、PHP 和 Lua 配置。
随机源为 `/dev/urandom`，不使用固定密码，也不把密码打印到安装日志。

- 最终配置：`/root/.gs/.env`，目录权限 `700`，文件权限 `600`。
- 安装中断恢复：`/root/.gs/credentials.pending.env`，权限 `600`。
- 成功保存最终配置后删除 pending 文件；失败重试时复用 pending 中的值。
- 重装保留已保存的自定义或随机密码，不每次重新生成。
- RHEL 安装流程识别旧版内置弱密码并迁移，使用旧密码认证后修改账号，保留已有数据库。
- RHEL 检测到已安装的 Redis/Valkey 时会同步凭据，不要求重新选择安装可选组件。
- 可显式指定 `TLBB_DB_PASS`、`TLBB_MYSQL_PASSWORD`、`TLBB_REDIS_PASSWORD`、
  `TLBB_GM_PASSWORD`、`TLBB_PRIVATE_KEY` 覆盖对应值。

`TL_MYSQL_PASSWORD` 是 root 密码；游戏账号使用 `TLBB_MYSQL_USER` 和
`TLBB_MYSQL_PASSWORD`，两者不再共用密码。已有服务端或 GM 网站在凭据变更后，
运行 `setini` 和 `upgm` 同步其配置；安装器不直接覆盖用户的游戏资源。

不要把 `.env`、pending 文件或带密码的应用配置上传到仓库或贴到公开日志。

## ODBC 自动适配

EL8/EL9/EL10 先检测现有服务端的 ELF 位数；没有服务端时按系统位数选择。
64 位环境安装原生 unixODBC 和可连接 MySQL 的原生连接器，不盲目安装 `unixODBC.i686`。
`mariadb-connector-odbc` 只是驱动，不会把 MySQL 服务端替换成 MariaDB。

驱动必须真实存在、ELF 位数匹配、动态依赖完整，才生成 DSN。原生位数配置后实际执行
`isql` 的 `SELECT 1`，同时验证游戏账号的随机密码。选定的位数、驱动路径写入 `.env`，
`/etc/odbc.ini` 权限为 `600`，`setini` 复用已选驱动及游戏账号。

可通过 `TLBB_ODBC_BITS=auto|32|64` 显式指定。32 位程序无法加载 64 位驱动；
EL10 不提供所需 i686 运行环境，检测到 32 位端时明确说明需要更换 64 位端或使用 EL9，
不能通过替换为 64 位驱动解决进程架构不兼容。

## 复测

2026-11-03 已在一次性 CentOS Stream 10 和 Stream 9 容器中完成以下实测：

| 场景 | Stream 10 | Stream 9 |
|---|---|---|
| 在线安装与随机密码认证 | MySQL 8.4.13，通过 | MySQL 8.0.46，通过 |
| Nginx / PHP-FPM / Redis 兼容服务 | Nginx 1.26.3 / PHP 8.3.36 / Valkey 8.1.10，通过 | Nginx 1.20.1 / PHP 8.0.30 / Redis 6.2.22，通过 |
| 原生 64 位 ODBC 连接 | libmaodbc，SELECT 1 通过 | libmaodbc，SELECT 1 通过 |
| 四项服务的真实自启链接 | 全部 enabled | 全部 enabled |
| 旧弱密码迁移、旧密码失效、数据保留 | 通过 | 通过 |
| setini / upgm 配置与 SQL 连接 | 通过 | 通过 |

```bash
bash tests/test_runtime_defaults.sh
bash tests/test_install_regressions.sh
bash tests/test_bootstrap_modes.sh
```

真实在线实装测试入口为 `tests/smoke_el10.sh`、`tests/smoke_el9.sh`，
只允许在显式设置 `TLBB_TEST_ALLOW_INSTALL=1` 的一次性容器执行。
测试启动真实数据库和可选服务，验证 SQL 导入、数据保留、生成密码认证、ODBC 连接、
配置权限及真实 systemd 自启链接。容器没有 systemd PID 1，不能替代完整虚拟机重启、
SELinux 或游戏服务端二进制的运行验收。

`tests/smoke_runtime_upgrade.sh` 可在上述实装容器保存的本地镜像中继续验证旧默认密码
迁移、旧密码失效、数据保留，以及 `setini`/`upgm` 的实际配置写入与数据库连接。
这些测试镜像含私有测试凭据，不应推送到公共镜像仓库。
