# Linux 在线安装修复 (2026-11-03)

适用本次反馈中的 CentOS Stream 10 / MySQL 8.4。修复保留现有数据库，
不会因启动或认证失败自动卸载 MySQL、移动数据目录或绕过授权表。

## 已确认的原因

- CentOS 10 Extras 原地址不存在。正确地址使用
  `centos-stream/SIGs/10-stream/extras/$basearch/extras-common/`。
  已添加官方镜像后备与 `skip_if_unavailable`，软件源全部不可用时中止安装。
- 包安装错误被丢弃。现在完整包管理日志写入
  `/var/log/tlbb-packages.log`，失败同时显示末尾错误。
- MySQL 临时密码重置第二步把 shell 的 `2>/dev/null` 写进 SQL。
  第一步成功后，后续仍用旧临时密码，最终无法登录。
- 在线源码未包含 Git 忽略的 `offline/sql/`。现在版本化初始 SQL 位于
  `sql/mysql51/`、`sql/mysql57/`、`sql/mysql80/`。
- 三库改写没有匹配实际 SQL 的 ``USE `tlbbdb`;`` 等带反引号语句。
- `CREATE USER IF NOT EXISTS` 不会修改已存在账号密码，现已配套 `ALTER USER`。
- 日志里 PHP 询问输入 `6` 被静默当作不安装。现在无效输入会重新询问。
- MySQL RPM 回退错误地按文件名第四段分组，下载了多个版本。现按准确包名
  保留各核心包最新版，并交由依赖求解器一次安装，不再强制忽略依赖。

## 使用修复后的代码

先将本次修复完整上传或同步到服务器的 `/root/.tlgame`。必须包括
`modules/rhel/database.sh` 和 `sql/`，不能只替换 `install.sh`。
本地修改尚未发布到 GitHub 时，原来的在线下载命令仍会取到旧代码。

本次附带的 `gstlenv-linux-fix-20261103.tar.gz` 是不含离线二进制的完整安装源码。
上传到服务器 `/root` 后可执行：

```bash
mkdir -p /root/.tlgame
tar -xzf /root/gstlenv-linux-fix-20261103.tar.gz -C /root/.tlgame
```

解压前建议备份旧 `/root/.tlgame`。该操作覆盖安装源码，不删除已有 `offline/`
或数据库目录。

建议先做服务器快照。确认数据库结构与当前服务器一致，不要随意在两库与三库间切换。
以下示例对应原日志的三库、MySQL 8.4 和默认测试密码：

```bash
cd /root/.tlgame
TLBB_NONINTERACTIVE=1 TLBB_MYSQL_VERSION=84 TLBB_DB_LAYOUT=3 \
TLBB_OPT_NGINX=1 TLBB_OPT_PHP=1 TLBB_OPT_REDIS=1 \
bash install.sh --online --dbpass 123456
```

安装器优先验证目标密码，其次尝试已知旧密码、私有恢复文件、旧版本留下的
`Gstest@<目标密码>`、本地空密码，最后处理日志中的临时密码。目标密码失效而
你知道当前密码时，可增加 `TLBB_DB_CURRENT_PASS='当前密码'`。
完全未知的密码不会自动通过 `skip-grant-tables` 重置。

密码校验组件与密码修改分开执行。首次生成的中间密码临时保存在
`/root/.gs/mysql-bootstrap.password` (0600)，验证成功后删除，支持中断续跑。

已有表的库不会自动重新导入，防止补装软件覆盖游戏数据。新导入中途失败会留下
`/root/.gs/sql-import/<库名>.pending`，再次运行会明确报错而非把半成品库视为成功。
先备份、查看真实 SQL 错误并修复，不要直接删除标记后盲目重复导入。
需要自定义 SQL 时，使用 `TLBB_SQL_DIR=/path/to/sql` 指定完整的同版本 SQL 目录。

## 验证

```bash
mysql -uroot -p
mysql --protocol=tcp -h127.0.0.1 -P3306 -uroot -p
mysql --protocol=tcp -h127.0.0.1 -P3306 -ugs -p
mysql -uroot -p -e 'SHOW DATABASES; SHOW TABLES FROM tlbbdb_main;'
nginx -t
php -m
REDISCLI_AUTH='gsgameshare.com' valkey-cli ping
systemctl --no-pager status mysqld nginx php-fpm valkey
```

CentOS 10 使用 Valkey 提供 Redis 协议服务。PHP 在线安装包含 CLI、FPM、
MySQL 扩展与 mbstring。远程登录还取决于主机监听地址、防火墙和云安全组，
本次未自动开放防火墙。默认密码仅适用于受限测试环境，生产环境应更换强密码，
并限制数据库访问来源。

## 测试范围

- `bash tests/test_install_regressions.sh`：密码状态迁移、SQL 转义与库名改写、
  已存在账号更新、认证检查、已有数据保留、失败退出及可选组件错误汇总。
- `tests/smoke_el10.sh`：仅允许在一次性 Docker 容器中显式开启安装测试。
  使用真实 CentOS Stream 10 软件源与 MySQL 包，检查首次临时密码重置、
  Socket/TCP 认证、三个 SQL 文件导入、旧中间密码恢复、特殊字符密码和
  Nginx/PHP/Valkey 实际进程。三库表数为 50 / 50 / 5。
- 容器没有 systemd PID 1，测试内用实际二进制启动服务；开机自启、SELinux、
  远程网络及真实游戏服务端仍需在目标 Linux 主机或完整 VM 上验证。
- el10 不提供 i686 库，不能把安装成功等同于支持 32 位老端。

2026-11-03 实测在线包版本：MySQL Community 8.4.13、Nginx 1.26.3、
PHP 8.3.36、Valkey 8.1.10。最终容器测试退出码为 0。
测试包含故意提交错误 SQL 并验证失败传播，因此测试日志中预期会出现一次
`ERROR 1064` 和一次“上次导入未完成”，两者不是初始化 SQL 导入失败。
