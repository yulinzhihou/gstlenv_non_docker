# CentOS Stream 9 在线安装修复 (2026-11-03)

## 本次日志确认的问题

执行默认的 `curl .../gsenv.sh | bash` 时，旧引导发现
`/root/offline-el9.tar.gz`，自动解压并追加 `--offline`。
这不是正常在线安装路径：缺少离线 MySQL 包后直接走官方 RPM 下载兜底，
没有优先使用 Stream 9 AppStream 的 `mysql-server`。

另外，CentOS 9 源模板中的 Extras 地址错误。现已使用
`SIGs/9-stream/extras/$basearch/extras-common/`，保留独立的国内与官方地址，
并为 BaseOS、AppStream、CRB 增加官方后备。不会在重试时把所有地址改成同一域名。

原日志未包含 `/var/log/tlbb-packages.log`，不能据此确定原机器上的具体依赖错误。
现在 RPM 直下安装失败会同时显示 DNF 错误末尾，不再只输出笼统失败。

## 更新后重试

默认一键引导现在明确使用在线模式。离线包可以保留，不必删除或改名；
已有数据库也不会被自动清空。建议先做服务器快照，再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash -s -- --online
```

预期日志包含：

```text
安装模式: [在线]
运行模式: [在线] 配置国内源, 使用 repo 安装组件
MySQL 8.0 通过系统源 (AppStream mysql-server) 安装完成
MySQL root/游戏账号认证及建库通过 (Socket + TCP)
```

按实际服务端选择数据库结构，不要为了重试而切换两库/三库。已知当前 root 密码
与本次目标密码不同时，可通过 `TLBB_DB_CURRENT_PASS` 提供当前密码；完全未知密码
不会自动绕过授权表重置。已有表的库保留原数据，不自动覆盖导入。

只有显式 `--offline` 或传给引导进程的 `TLBB_OFFLINE_MODE=1` 才启用离线组件。
命令行参数优先，多个模式参数取最后一个。在线模式不自动解压离线包。
`--offline-dir` 指定的目录也用于显式离线模式的解压目标。
引导下载源码仍需网络，完全离线需先上传完整源码。

## 实测结果

使用全新 `quay.io/centos/centos:stream9` 容器、真实在线软件源，
`TLBB_OFFLINE_MODE=0`，离线目录不存在。测试退出码为 0。

| 项目 | 结果 |
| --- | --- |
| MySQL | AppStream `mysql-server-8.0.46-1.el9.x86_64` |
| 认证 | root Socket、root TCP、游戏账号 TCP 均通过 |
| 初始三库 | `tlbbdb_main` 50 表，`tlbbdb_10` 50 表，`web` 5 表 |
| Nginx | 1.20.1，配置检查与进程启动通过 |
| PHP | 8.0.30，FPM、mysqli、mbstring 检查通过 |
| Redis | 6.2.22，密码认证 PING 返回 PONG |
| 重跑 | 保留已有表及测试记录，恢复旧中间密码 |
| 其他 | 两库导入、特殊字符密码、错误 SQL 与半成品标记检查通过 |

复现安装测试：

```bash
docker run --rm --cap-add=SYS_NICE \
  -e TLBB_TEST_ALLOW_INSTALL=1 -v "$PWD:/work:ro" \
  quay.io/centos/centos:stream9 bash /work/tests/smoke_el9.sh
bash tests/test_bootstrap_modes.sh
bash tests/test_install_regressions.sh
```

仅在一次性测试容器运行实装测试。Stream 9 软件包的 mysqld 带
`cap_sys_nice=ep`，容器需添加对应能力，否则内核拒绝执行；这不是要求修改真实
服务器安全配置。容器内用真实软件二进制代替 systemd 启动，开机自启、SELinux、
远程防火墙与游戏服务端仍需目标主机或完整 VM 验证。

测试故意导入无效 SQL，日志中的一次 `ERROR 1064` 和“上次导入未完成”
用于验证错误传播，不代表初始三库导入失败。

同一套实装脚本也已在全新 CentOS Stream 10 容器复跑通过，
确认 MySQL 8.4、Nginx、PHP、Valkey 的在线安装与数据库操作未回归。
