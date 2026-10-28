# TLBB 原生环境安装包 (src)

> **非 Docker** 的《天龙八部》服务端运行环境万能安装器，以**源码脚本**方式开发。
> 参考开源 gstlenv（Docker 版）的命令体系与配套脚本功能，反 Docker 化为**原生系统安装**。
> 覆盖主流 Linux 发行版 × 全版本，国内源优先、离线组件兜底。

---

## 一、支持系统矩阵

### RHEL 系（yum/dnf，el5 ~ el10）

| 系统 | 版本 | 安装家族 | 国内源 | 备注 |
|---|---|---|---|---|
| CentOS | 5.1 / 5.8 / 5.11 | el5 | 阿里云 centos-vault 5.11 | 已 EOL，离线 rpm 兜底 |
| CentOS | 6.0 ~ 6.10 | el6 | 阿里云/163 vault | 已 EOL |
| CentOS | 7.0 ~ 7.9 | el7 | 阿里云/腾讯/163/搜狐 vault | 全链路验证 |
| CentOS | 8.0 ~ 8.5 | el8 | 阿里云/腾讯/163 vault | 已 EOL |
| CentOS Stream | 9 / 10 | el9 / el10 | 阿里云/腾讯/华为 | |
| 阿里云 Alinux | 2 / 3 / 4 | el7 / el8 / el9 | mirrors.aliyun.com | |
| 阿里云 Anolis | 8 / 23 | el8 / el9 | mirrors.aliyun.com | |
| 腾讯云 TencentOS | 2 / 3 / 4 | el7 / el8 / el9 | mirrors.cloud.tencent.com | |
| 华为 openEuler | 20~22 / 24+ | el8 / el9 | mirrors.huaweicloud.com | |
| 华为 EulerOS | 2.x | el7 | mirrors.huaweicloud.com | |
| Rocky / AlmaLinux | 8 / 9 | el8 / el9 | 阿里云 | |
| Oracle / 其他 RHEL 兼容 | 5~10 | 对应 el | 自动匹配 | |

### Debian 系（apt）

| 系统 | 版本 | 源策略 |
|---|---|---|
| Ubuntu | 12.04 / 13.x / 14.04 / 15.x | old-releases + 清华 |
| Ubuntu | 16.04 / 17.x / 18.04 / 19.x | old-releases + 清华 |
| Ubuntu | 20.04 / 22.04 / 24.04 / 25.x / 26.x | 阿里云/腾讯/华为 |
| Ubuntu | 20.10 / 21.x / 22.10 / 23.x / 24.10 | old-releases + 清华 |
| Debian | 10 (buster) | archive.debian.org + 清华 |
| Debian | 11 (bullseye) | 阿里云 + 归档兜底 |
| Debian | 12 (bookworm) / 13 (trixie) | 阿里云/腾讯/华为 |
| Debian | 14~18（未来版） | 自动回退最新稳定版 |

---

## 二、目录结构

```
src/
├── install.sh               ★ 万能安装入口（自动识别系统 → 全流程安装）
├── README.md                ★ 本文档
├── modules/                 安装引擎
│   ├── common.sh            公共函数（日志/检查/离线定位/包管理）
│   ├── detect.sh            系统识别（发行版 × 版本 → 安装家族）
│   ├── rhel/install.sh      RHEL 系安装流程（el5~el10 + 云厂商）
│   └── debian/install.sh    Debian 系安装流程（Ubuntu/Debian 全版本）
├── repos/                   ★ 国内安装源（RHEL 系 18 个 .repo + Debian 系 apt/ 34 个源，按版本区分）
│   ├── centos5.repo ...      RHEL 系 yum/dnf 源（centos5~10 + 云厂商）
│   └── apt/                  Debian 系 apt 源（ubuntu-*.list ×25 + debian-*.list ×9）
├── offline/                 ★ 离线组件（按版本区分，不入 git）
│   ├── el5/                 CentOS 5：unixODBC/mysql-odbc rpm + conf
│   ├── el6/                 CentOS 6：unixODBC.rpm + mysql-odbc.rpm + libmyodbc3
│   ├── el7/                 CentOS 7：MySQL 5.1 rpm + unixODBC 2.2.11 + 32/64 位驱动
│   ├── el8_el9_el10/        现代 RHEL：32 位驱动 + unixODBC 源码
│   ├── deb-common/          Debian 系：32 位驱动 + unixODBC 源码 + 备用驱动
│   └── sql/                 tlbbdb.sql / web.sql（全系通用）
├── offline-packs/           ★ 版本化离线压缩包（scripts/pack_offline.sh 生成，不入 git）
├── cmd/                     ★ tl_* 全局管理命令（参考 gstlenv，反 Docker 化）
│   ├── tl.sh                总命令菜单
│   ├── untar.sh / setini.sh / runtlbb.sh / runtop.sh
│   ├── close.sh / restart.sh / swap.sh
│   ├── backup.sh / restore.sh / reset.sh / delbak.sh / logbak.sh
│   ├── setvalid.sh / setpoint.sh / curgs.sh
│   ├── change.sh / rebuild.sh / remove.sh
│   └── gslog.sh / rmlog.sh
├── scripts/                 版本一键脚本（ubuntu.sh / debian.sh 等）
└── docs/                    文档
    ├── 安装说明.md
    ├── 环境创建说明.md
    └── 注意事项.md
```

---

## 三、快速开始

### 3.0 在线 / 离线双模式（重要）

安装器支持两种运行模式，自动检测或手动指定：

```bash
# 在线模式（默认）：自动检测网络 → 配置国内源 → 使用 repo 安装组件
bash install.sh
# 强制在线：显式指定
bash install.sh --online

# 离线模式：无网络虚拟机 / 单机，使用本地 rpm/deb 命令安装组件
bash install.sh --offline
# 自动模式：检测不到网络时自动进入离线模式
bash install.sh
```

**离线模式组件来源**（按发行版版本 + MySQL 档位组织）：
- `offline/el5|el6|el7/`：内置驱动 + unixODBC + MySQL 5.1（el7 MySQL.tar.gz）离线包
- `offline/rpm-packages/<elX>/mysql57|mysql80/`：联网机器上用 `dnf download --resolve` / `yumdownloader` 下载的 MySQL 官方 rpm（el8+ 离线必需）
- `offline/rpm-packages/<elX>/compat/`：unixODBC / 32 位兼容库 rpm
- `offline/deb-packages/mysql57|mysql80/`：联网机器上用 `apt-get download` 下载的 MySQL deb（Debian 系离线必需）
- 生成工具：`bash scripts/pack_offline.sh`（打包内置组件）/ `--full <版本> [--mysql 51|57|80]`（联网下载依赖）

**数据库档位**（对齐 gstlenv 环境编号，不用 MariaDB）：

| 档位 | 适用系统 | 来源 |
|---|---|---|
| MySQL 5.1 | el5/el6/el7、Ubuntu 12~16 | yum vault 归档 / 内置离线包 / 系统源 5.5/5.6 |
| MySQL 5.7 | el7/el8、Ubuntu 18 | 官方源（阿里云/华为云镜像）/ 系统源 |
| MySQL 8.0 | el9/el10、Ubuntu 20+、Debian 10+ | 官方源 / 系统源 / Debian 官方 apt 源 |

> 默认按系统自动选择，可用 `TLBB_MYSQL_VERSION=51|57|80` 或安装时菜单（1/2/3）覆盖。

### 3.1 一键安装（推荐）

```bash
# 1. 上传整个 src 目录到服务器任意位置（如 /root/src）
# 2. 进入目录执行
cd /root/src
bash install.sh

# 免交互（指定数据库密码，默认 123456 对齐 gstlenv）
TLBB_DB_PASS=你的密码 bash install.sh
# 指定 MySQL 档位（可选，默认 auto 按系统）
TLBB_MYSQL_VERSION=57 bash install.sh
```

安装过程自动完成：识别系统 → 选择 MySQL 档位 → 配置国内源 → 装 32 位兼容库 → 装数据库（MySQL 5.1/5.7/8.0）→ 导入 tlbbdb/web → 装 unixODBC + 驱动 → 部署 tl_* 命令。

### 3.2 创建游戏环境（安装后）

```bash
# 1. 上传服务端压缩包到 /root（tlbb.tar.gz 或 tlbb.zip）
# 2. 解压服务端
tl_untar
# 3. 写入数据库配置
tl_setini
# 4. 开启服务端
tl_runtlbb
# 5. 查看状态
tl_runtop
```

### 3.3 常用运维

```bash
tl                        # 查看全部命令帮助
tl_backup                 # 备份数据库（/root/backup/）
tl_restore                # 还原数据库
tl_reset                  # 删档重导（谨慎！）
tl_setvalid 账号 1        # 封号
tl_setvalid 账号 0        # 解封
tl_setpoint 账号 5000     # 设置充值点数
tl_swap 4                 # 增加 4GB 虚拟内存
tl_change                 # 换端
tl_rebuild                # 重构环境
tl_remove                 # 卸载
```

---

## 四、命令手册（gstlenv 原命令名，反 Docker 化对照）

> 命令以 **gstlenv 原命令名**部署到 `/usr/local/bin`（untar/setini/runtlbb/.../gs/link/gstl），同时保留 `tl_` 前缀兼容名（tl_untar/tl_setini...）。帮助入口：`gs`（gstlenv 同款菜单）与 `tl`（菜单）。

| 编号 | 命令 | 原 gstlenv（Docker） | 本包（原生） |
|---|---|---|---|
| 01 | untar | docker exec 解压 | tar/unzip 解压到 /home/tlbb |
| 02 | setini | docker exec 写 ini | sed 写 ServerInfo.ini |
| 03 | runtlbb | docker start 容器 | nohup bash run.sh 后台启动 |
| 04 | runtop | docker ps 容器状态 | 检查 ShareMemory/Login/World/Server 进程 |
| 05 | link | docker-compose exec 进容器 | 直接进入 /home/tlbb 服务端目录（原生无容器） |
| 06 | swap | 容器内加 swap | 本机增加虚拟内存 |
| 07 | rebuild | 重建容器 | 重构本机环境（备份→重建→还原） |
| 08 | remove | docker rm 容器 | 移除本机环境与命令 |
| 09 | setconfig | 重写容器配置 | 重写 /root/.tlbb/tlbb.env 端口/密码 + 改数据库密码 |
| 10 | change | 容器换端 | 本机备份换端 |
| 11 | restart | docker restart | 本机重启数据库+服务端 |
| 12 | gsbak | 容器内定时备份 | crontab 定时 mysqldump + 版本备份 |
| 13 | upcmd | gitee 拉取最新命令 | 从环境包 cmd/ 重新部署命令到 /usr/local/bin |
| 14 | upgm | nginx 容器 + DBConfig.php | 生成 /tlgame/www/gm + DBConfig.php |
| 15 | upow | nginx 容器站点 | 创建 /tlgame/www/ow 开服网站目录 |
| 16 | step | 容器内分步启动 | 解析 run.sh 分步启动进程 |
| 17 | gstl | 下载镜像 compose up | 检查环境 → 显示配置(curgs) + 虚拟内存(swap) |
| 18 | backup | docker exec mysqldump | 本机 mysqldump |
| 19 | close | docker stop | 本机关服 |
| 20 | gslog | docker logs | 本机日志 |
| 21 | rmlog | 容器内删除日志 | 本机删除日志 |
| 22 | curgs | docker inspect | 读取 /root/.tlbb/tlbb.env + odbc.ini |
| 23 | setpoint | docker exec SQL | 本机 mysql 执行 SQL |
| 24 | reset | docker exec 删库重导 | 本机 drop/create + 导入 |
| 25 | setvalid | docker exec SQL | 本机 mysql 执行 SQL |
| 26 | restore | docker exec mysql | 本机 mysql 导入 |
| 27 | delbak | 容器内删除备份 | 本机删除备份 |
| 28 | gsfix | 重装 docker + 环境 | 修复本机组件/驱动/数据库 |
| 29 | logbak | 容器内定时日志备份 | crontab 定时备份日志 |
| - | color | 容器内颜色库 | /usr/local/bin/color 公共库 |
| - | gs | 帮助菜单 | 同款帮助菜单（gs / gs 01 / gs untar） |

---

## 五、安装内容明细

| 组件 | 说明 | 离线 |
|---|---|---|
| MySQL 5.1/5.7/8.0 | el5/6/7 离线 MySQL 5.1；el8 MySQL 5.7；el9/10+8.0；Ubuntu 20+/Debian 8.0（不用 MariaDB） | el6/7 ✅（5.7/8.0 走 pack_offline 生成） |
| unixODBC | ODBC 管理器（el5/6/7 离线 rpm；el8+/deb 走源或源码） | el5/6/7 ✅ |
| MySQL ODBC 3.51 驱动 | 32 位 libmyodbc3（服务端必须） | ✅ |
| MySQL ODBC 5.1 驱动 | 64 位 libmyodbc5（el7+ 管理工具用） | ✅ |
| glibc.i686 等 32 位兼容库 | 服务端为 32 位进程，必须 | 走系统源 |
| tlbbdb.sql / web.sql | 游戏库表结构 | ✅ |
| odbc.ini / odbcinst.ini | 自动生成 | ✅ |

---

## 六、离线包管理（不进 git 版本管理）

离线组件为大体积二进制，**不进入 git 版本管理**（见 `.gitignore`），按发行版版本独立打包：

```bash
# 1) 打包内置离线组件为版本化压缩包（el5/el6/el7/el8_9_10/deb/sql）
bash scripts/pack_offline.sh
# 输出: offline-packs/el5-offline.tar.gz, el7-offline.tar.gz, ...

# 2) 在联网机器上生成某版本完整离线包（MySQL 档位 + 兼容库 + 驱动）
bash scripts/pack_offline.sh --full el7                 # RHEL: MySQL 5.1 内置 + yumdownloader
bash scripts/pack_offline.sh --full el8 --mysql 57      # el8 指定 MySQL 5.7 rpm
bash scripts/pack_offline.sh --full el9 --mysql 80      # el9 指定 MySQL 8.0 rpm
bash scripts/pack_offline.sh --full ubuntu24            # Debian: apt-get download MySQL 8.0 deb
# 下载产物放入 offline/rpm-packages/<版本>/mysql<档位>/ 或 offline/deb-packages/mysql<档位>/

# 3) 在目标服务器上解压离线包
bash scripts/pack_offline.sh install el7
```

> 说明：仓库 clone 后需先通过 `pack_offline.sh` 重新生成 offline/（或直接从 `offline-packs/` 解压），再执行安装。

---

## 七、文档导航

- [安装说明](docs/安装说明.md) — 系统要求、安装前准备、安装步骤、验证
- [环境创建说明](docs/环境创建说明.md) — 从零到开服的完整流程
- [注意事项](docs/注意事项.md) — 端口/防火墙/安全/常见问题

---

*源码开发 · 非 Docker · 国内源优先 · 离线兜底 · 参考 gstlenv 命令体系*
