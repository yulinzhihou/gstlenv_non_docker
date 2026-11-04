# Billing 程序与命令提示（2026-11-04）

## 默认提供程序

环境现在带有参考项目 `gstlenv/config/ini.tar.gz` 中的 `billing32`、`billing64`，
来源版本、原压缩包及程序 SHA256、参考项目许可记录在 `assets/billing/`。
不复制参考包里的旧数据库密码、INI 或默认 YAML 配置。

选择依据是 **Linux 主机架构**，不是 MySQL 版本，也不是游戏服务端的位数。
x86-64 使用 `billing64`，32 位 x86 使用 `billing32`。其他架构没有内置程序，
需要上传匹配该主机架构的版本；不会把不匹配的程序假装安装成功。

## 部署优先级

1. `/root/billing.tar.gz`。只要此文件存在就优先检查，失败会报错停止，不静默改用内置程序。
2. 已安装的 `/tlgame/billing/billing`（兼容迁移旧 `/home/billing` 中缺少的文件）。
3. 环境自带、SHA256 校验通过且 ELF 架构匹配的程序。

上传包支持平铺的 `billing`、嵌套的 `billing/billing`，以及只有一份匹配架构的
`billing32` / `billing64`。包中若出现多份同名候选程序、危险路径、无效 ELF 或错误架构，
部署返回失败。只读取选中的可执行文件，不展开包内的链接和配置文件。
自定义程序仍需兼容现有 `billing up -d` / `billing stop` 启停接口。

新安装将程序放在 `/tlgame/billing/billing`，运行目录必须是真实目录，不再创建
`/home/billing` 兼容链接。旧 `/home/billing` 中缺少的程序、配置和日志会复制到
`/tlgame/billing`，已有同名文件优先保留，原目录不删除。旧 Billing 仍在运行时拒绝迁移，
需要先关服，不会擅自终止它。迁移成功后记录标记，避免每次重复导入旧数据。
`untar`、`setini` 备份并把 `run.sh` 的旧 Billing 路径替换为 `/tlgame/billing`。

上传包保留原名。程序内容改变时，旧程序保存在 `${BACKUP_DIR}/billing-before-*`，
默认 `/tlgame/backup`；内容不变不会重复备份。
包内 `config.yaml` 不覆盖运行配置，真正配置由 `setini` 从私有 `.env` 生成。
Billing 配置及其源码目录中的副本权限为 `600`，可执行文件为 `755`；
不再对 Billing 目录或整个游戏目录递归设置 `777`。

## 安装与升级

全新安装自动准备 Billing 程序，但不提前启动登录验证服务。上传游戏包后依次执行：

```bash
untar
setini
# 需要在线 GM 时执行: upgm
runtlbb
```

`untar` 成功提示会包含 Billing 状态，以及 `setini`、可选 `upgm` 和 `runtlbb` 的顺序。
`setini` 也独立执行同一套 Billing 准备逻辑，因此已经解压服务端的机器不必重复解压。
W 机验证模式 (`IS_DLQ=1`) 不部署或启动本机 Billing。
此模式若 `run.sh` 仍含本机 Billing 启动项，检查会要求手动移除该项后重试，
不会悄悄删除上传脚本中的命令。

已经使用上一版更新器的机器，首次升级执行两次：

```bash
upcmd && upcmd
hash -r
setini
```

原因是上一版更新器只同步 `cmd/`，第一次取得新版更新器，第二次由新版同步
`assets/billing/`。以后只需执行一次 `upcmd`。
新版会把命令和 Billing 内置资源一起校验、备份、更新；中途失败尝试一起回滚。
更新资源本身不替换在用的 Billing，不修改数据库、密码或游戏数据。

需要自己的 Billing 时，先上传 `/root/billing.tar.gz`，再执行 `setini` 即可。
修改运行中的程序前先停服，检查配置后再开服；准备过程不会擅自停止或重启现有服务。
正常部署时不执行包中的程序，也不自动证明实际登录器和协议兼容。

## 验证范围

`tests/test_billing.sh` 覆盖内置选择、重复部署、已有目录、旧嵌套链接、
上传包优先、旧程序备份、配置/日志保留、损坏/歧义/路径/架构失败，以及
原生目录迁移与运行中旧程序的保护。
`tests/test_upcmd.sh` 检查内置资源校验和命令/资源共同回滚。
`tests/smoke_billing.sh` 在一次性容器中运行真实 `untar`、`setini`，检查提示、
上传包优先、私有且正确引用的密码配置、启动命令去重和 W 机模式。
不启动用户游戏或登录器，不以 ELF/哈希校验代替实际协议联调。
