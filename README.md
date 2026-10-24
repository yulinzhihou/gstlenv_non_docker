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
├── repos/                   ★ 国内 yum/dnf 源（18 个 .repo，按版本区分）
├── offline/                 ★ 离线组件（按版本区分）
│   ├── el5/                 CentOS 5：unixODBC/mysql-odbc rpm + conf
│   ├── el6/                 CentOS 6：unixODBC.rpm + mysql-odbc.rpm + libmyodbc3
│   ├── el7/                 CentOS 7：MySQL 5.1 rpm + unixODBC 2.2.11 + 32/64 位驱动
│   ├── el8_el9_el10/        现代 RHEL：32 位驱动 + unixODBC 源码
│   ├── deb-common/          Debian 系：32 位驱动 + unixODBC 源码 + 备用驱动
│   └── sql/                 tlbbdb.sql / web.sql（全系通用）
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

### 3.1 一键安装（推荐）

```bash
# 1. 上传整个 src 目录到服务器任意位置（如 /root/src）
# 2. 进入目录执行
cd /root/src
bash install.sh

# 免交互（指定数据库密码）
TLBB_DB_PASS=你的密码 bash install.sh
```

安装过程自动完成：识别系统 → 配置国内源 → 装 32 位兼容库 → 装数据库 → 导入 tlbbdb/web → 装 unixODBC + 驱动 → 部署 tl_* 命令。

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

## 四、tl_* 命令手册（反 Docker 化对照）

| 命令 | 原 gstlenv（Docker） | 本包（原生） |
|---|---|---|
| tl_untar | docker exec 解压 | tar/unzip 解压到 /home/tlbb |
| tl_setini | docker exec 写 ini | sed 写 ServerInfo.ini |
| tl_runtlbb | docker start 容器 | nohup bash run.sh 后台启动 |
| tl_backup | docker exec mysqldump | 本机 mysqldump |
| tl_restore | docker exec mysql | 本机 mysql 导入 |
| tl_reset | docker exec 删库重导 | 本机 drop/create + 导入 |
| tl_setvalid / tl_setpoint | docker exec SQL | 本机 mysql 执行 SQL |
| tl_curgs | docker inspect | 读取 /root/.tlbb/tlbb.env + odbc.ini |
| tl_swap / tl_close / tl_gslog 等 | 容器操作 | 原生系统操作 |

---

## 五、安装内容明细

| 组件 | 说明 | 离线 |
|---|---|---|
| MySQL / MariaDB | el5/6/7 离线 MySQL 5.1；el8+ MariaDB | el6/7 ✅ |
| unixODBC | ODBC 管理器（el5/6/7 离线 rpm；el8+/deb 走源或源码） | el5/6/7 ✅ |
| MySQL ODBC 3.51 驱动 | 32 位 libmyodbc3（服务端必须） | ✅ |
| MySQL ODBC 5.1 驱动 | 64 位 libmyodbc5（el7+ 管理工具用） | ✅ |
| glibc.i686 等 32 位兼容库 | 服务端为 32 位进程，必须 | 走系统源 |
| tlbbdb.sql / web.sql | 游戏库表结构 | ✅ |
| odbc.ini / odbcinst.ini | 自动生成 | ✅ |

---

## 六、文档导航

- [安装说明](docs/安装说明.md) — 系统要求、安装前准备、安装步骤、验证
- [环境创建说明](docs/环境创建说明.md) — 从零到开服的完整流程
- [注意事项](docs/注意事项.md) — 端口/防火墙/安全/常见问题

---

*源码开发 · 非 Docker · 国内源优先 · 离线兜底 · 参考 gstlenv 命令体系*
