# TLBB 原生环境安装包 (src) —— gstlenv 非 Docker 版

> **非 Docker** 的《天龙八部》服务端运行环境万能安装器，以**源码脚本**方式开发。
> 当前环境相当于是开源 [gstlenv](https://gitee.com/yulinzhihou/gstlenv) 的**非 Docker 原生版**：
> 命令体系（gs 原命令名）、环境配置（/root/.gs/.env）、数据目录（/tlgame）与 gstlenv **完全一致**，
> 仅将容器安装替换为本机系统安装（在线 repo / 离线 rpm、deb 双模式）。
> 项目地址：https://github.com/yulinzhihou/gstlenv ｜ https://gitee.com/yulinzhihou/gstlenv

---

## 项目支持

查看支持的服务器系统版本（覆盖主流 Linux 发行版 × 全版本，x86_64 一键安装）：

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
| Debian | 11 (bullseye) | 阿里云 + 归档兜底；**MySQL 官方 apt 8.0.37 离线包已入库** |
| Debian | 12 (bookworm) / 13 (trixie) | 阿里云/腾讯/华为；**MySQL 官方 apt 8.0.37 离线包已入库** |
| Debian | 14~18（未来版） | 自动回退最新稳定版 |
| Fedora | 34 ~ 38 | archive.fedoraproject.org；**MySQL 8.0.36 官方通用二进制 + compat/odbc/redis 离线包已入库** |

- 本教程支持各种云服务器，虚拟机系统，**可在线，可离线**
- 增加敏感配置项可以自定义，简单方便。如：数据库密码，端口等（`setconfig`）
- 集成分步调试开服的命令（`step`），可以更好的排错
- 集成分步开服、日志查看、定时备份、封号解封、充值点数等全套运维命令（与 gstlenv 命令名一致）
- 本操作手册仅供学习使用，请勿用于商业用途，如有侵权，请与本人联系！

### 前期准备

- 安装好指定条件环境的服务器系统（64 位，≥2GB 内存）
- 关闭防火墙，默认需要在安全组开放指定端口 **`51888`  `3306`  `13580`  `15680`  `21818`**（对齐 gstlenv，其中数据库端口由 33061 收敛为本机 3306）
- 如果想自己定义相应端口，则使用 `setconfig` 修改后，再去开放对应的安全组端口号

## 快速入门

### 视频教程（小白新手快速从 0 到 1，教程为 Docker 版，原生版操作步骤相同，仅环境安装方式不同）
- [第一课：服务器环境安装（虚拟机+云主机）](https://www.bilibili.com/video/BV1oN411y7r7/)
- [第二课：本机运行环境的准备工作](https://www.bilibili.com/video/BV1Jh411c7ud/)
- [第三课：安装 GS 环境并架设服务端程序](https://www.bilibili.com/video/BV1eu4y1f7Pd/)
- [第四课：安装客户端及更新补丁](https://www.bilibili.com/video/BV1Cz4y1B7RU/)
- [第五课：GM工具使用](https://www.bilibili.com/video/BV1Gh411c7GD/)
- 第六课：其他功能介绍与展示

### 一、环境安装步骤以及服务端上传启动（服务端）

- 第 1 步：使用 `root` 用户登录，**否则可能会出现报错，建议安装到 `root` 根目录**。安装环境有两种方式：

**方式 A（推荐）在线一键安装** —— 一条命令自动下载源码并安装（对齐 gstlenv 的 `curl | bash` 方式）：

```bash
curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash
```

> 安装过程：自动检测 root → 下载源码到 `/root/.tlgame` → 识别系统 → 选择 MySQL 档位（1=5.1 / 2=5.7 / 3=8.0，回车=auto）→ 配置国内源 → 装 32 位兼容库 → 装数据库（MySQL 5.1/5.7/8.0）→ 导入 tlbbdb/web → 装 unixODBC + 驱动 → 部署 gs 原命令名 + gsctl。
>
> 可选参数：
> - 指定数据库密码：`... | bash -s -- --dbpass 你的密码`
> - 强制在线模式（配置国内源 repo 安装）：`... | bash -s -- --online`
> - 离线模式（无网络，需先解压离线组件附件到 `/root/.tlgame/offline-packs/`）：`... | bash -s -- --offline`

**方式 B（离线/手动）下载部署环境的项目**，将本 `src` 包上传到服务器任意目录（如 `/root/src`），执行安装：

```bash
cd /root/src
bash install.sh
```

> 安装过程自动完成：识别系统 → 选择 MySQL 档位（1=5.1 / 2=5.7 / 3=8.0，回车=auto）→ 配置国内源 → 装 32 位兼容库 → 装数据库（MySQL 5.1/5.7/8.0）→ 导入 tlbbdb/web → 装 unixODBC + 驱动 → 部署 gs 原命令名 + gsctl。

- 第 2 步：**如果想使用默认配置（默认的端口，默认的数据库密码 123456 等），可以跳过此步骤**

```bash
# 执行此命令，进入交互配置界面（可修改服务器模式/端口/数据库密码等）
setconfig
```

- 第 3 步：上传服务端到 `/root` 下，服务端的名称只能是  `tlbb.tar.gz` 或者 `tlbb.zip` 否则后面的操作会报错

```bash
# 第一种方式：点击 `xshell` 软件的 `sftp` 按钮，进行 `sftp` 命令行传输模式
# 第二种方式：用 `winscp` 软件或者其他上传软件都行，只要把服务端上传到 `/root` 目录下即可

# 此命令只适用于 xshell 软件的 sftp 命令行窗口，请仔细查看
cd ~
put
```

- 第 4 步：解压上传的服务端 **（不需要考虑是哪种格式，使用此命令即可完成解压操作）**

```bash
untar
```

- 第 5 步：设置配置文件 **（将配置文件进行覆盖，此配置文件会按照 `/root/.gs/.env` 文件里面定义的进行替换，没有更改的话则使用默认值）**

```bash
setini
```

- 第 6 步：开启服务端，等待结果

```bash
runtlbb
```

- 第 7 步：使用命令查看服务端运行状态

```bash
runtop
```

>   恭喜你！到此，服务端已经正确开启。
>
>   至此，服务器服务端版本开启已经完成 ，下列命令不需要逐条执行，如遇到其他问题才需要进行分步调试
>
>   只有在修改版本与调试功能的时候才需要使用下列命令进行分步开服，正常启动不需要使用以下命令。

### 二、安装步骤（客户端）

- 安装最新官方[客户端](http://tl.changyou.com/download/index.shtml) ，或者下载指定版本的[客户端](https://qm.qq.com/cgi-bin/qm/qr?k=U88GIGoFjAcy9kkX3hJ-Xv0qRvSXB3ej) （进技术交流群：902281567 获取）

- 解压补丁包
- 更新补丁
- 配置单机测试使用的登录器
- 联网登录器

### 三、网站配置（服务端）

- 准备网站源代码文件，有能力的自己写。
- 先运行 `upow` 命令后，按指定参数配置好
- 将文件上传到 **`/tlgame/www/ow`** 这个目录下面（首页必须为 index.html / index.htm / default.html / default.htm 中的一种）

### 四、内部集成命令
- 使用 `gs` 命令进入命令帮助提示，使用 `gsctl` 统一入口执行（见下方「常用运维」与「命令手册」）

### 五、捐赠
- 如果感觉项目对你有点帮助，请支持一下我们

| 支付宝扫码捐赠    | 交流群（QQ） | 微信支付捐赠         |
| ----------------- | -------------------- | -------------------- |
| <img src="https://gitee.com/yulinzhihou/gstlenv/raw/master/images/alipay.png" style="zoom:50%;" /> | <img src="https://gitee.com/yulinzhihou/gstlenv/raw/master/images/qqgroup.png" style="zoom:40%;" /> | <img src="https://gitee.com/yulinzhihou/gstlenv/raw/master/images/wechatpay.png" alt="w" style="zoom:50%;" /> |

### 六、视频教程与技术交流群

-   技术交流群：902281567（原群被封）
-   有需要可以进电报群（PS:不经常看）[https://t.me/gstlenv](https://t.me/gstlenv)
-   项目地址：https://github.com/yulinzhihou/gstlenv ｜ https://gitee.com/yulinzhihou/gstlenv

### 七、常见问题集合（不定期查看，欢迎反馈，我们一起把环境壮大）

- [https://github.com/yulinzhihou/gstlenv/wiki](https://github.com/yulinzhihou/gstlenv/wiki)
- [https://gitee.com/yulinzhihou/gstlenv/wiki](https://gitee.com/yulinzhihou/gstlenv/wiki)
- 也可以提交 issue：https://gitee.com/yulinzhihou/gstlenv/issues

---

## 一键安装（推荐）

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

**在线 / 离线双模式**（自动检测，也可手动指定）：

```bash
# 在线模式（默认）：自动检测网络 → 配置国内源 → 使用 repo 安装组件
bash install.sh
# 强制在线：显式指定
bash install.sh --online
# 离线模式：无网络虚拟机 / 单机，使用本地 rpm/deb 命令安装组件
bash install.sh --offline
```

## 创建游戏环境（安装后）

```bash
# 1. 上传服务端压缩包到 /root（tlbb.tar.gz 或 tlbb.zip）
# 2. 解压服务端
untar
# 3. 写入数据库配置（ServerInfo.ini / LoginInfo.ini / ShareMemInfo.ini / odbc.ini / billing config.yaml）
setini
# 4. 开启服务端
runtlbb
# 5. 查看状态
runtop
```

## 常用运维

```bash
gs                        # 查看全部命令帮助（gstlenv 同款菜单）
gsctl <命令> [参数...]    # 统一命令入口（替代原 tl_* 前缀），如: gsctl untar / gsctl setconfig
setconfig                 # 重新设置配置参数（服务器模式/端口/数据库密码/Redis密码）
backup                    # 备份版本+数据库（/tlgame/backup/）
restore web 备份文件路径   # 还原数据库（web / tlbbdb）
reset                     # 删档重导（谨慎！先 backup）
setvalid 账号 1           # 封号
setvalid 账号 0           # 解封
setpoint point 5000 账号  # 设置充值点数（类型: point/yuanbao/zengdian/menpaipoint/guildpoint/points/vmoney）
swap 4                    # 增加 4GB 虚拟内存（默认 4G）
change                    # 换端
rebuild                   # 重构环境
remove                    # 移除环境
gsbak                     # 定时备份（默认 1 小时一次，保留 10 份）
delbak 5                  # 删除旧备份（保留 5 份）
logbak cron 1 10          # 定时日志备份（1 小时一次，保留 10 份）
gslog                     # 查看服务端日志
rmlog                     # 清除服务端日志
step                      # 分步调试开服
upgm                      # 配置在线 GM 网站
upow                      # 配置开服网站
curgs                     # 查看当前环境配置
link mysql                # 进入 MySQL（server=服务端目录 / nginx / redis / php）
gstl                      # 环境安装检测（未安装提示 install.sh）
gsfix                     # 修复环境安装
transfer                  # 重新构建环境版本（1=CS6+5.1 2=CS7+5.1 3=CS7+5.7 4=CS9+8.0）
```

## 命令手册（gstlenv 原命令名，反 Docker 化对照）

> 命令以 **gstlenv 原命令名**部署到 `/usr/local/bin`（untar/setini/runtlbb/.../gs/link/gstl），与 gstlenv 完全一致。
> 如需统一前缀入口，使用 `gsctl <命令> [参数...]`（如 `gsctl untar` 等价于 `untar`）。
> 帮助入口：`gs`（gstlenv 同款菜单，`gs 01` / `gs untar` 查看并执行）。

| 编号 | 命令 | 原 gstlenv（Docker） | 本包（原生） |
|---|---|---|---|
| 01 | untar | docker exec 解压 | tar/unzip 解压到 /tlgame/tlbb |
| 02 | setini | docker exec 写 ini | 写 ServerInfo/LoginInfo/ShareMemInfo + odbc.ini + billing config.yaml |
| 03 | runtlbb | docker start 容器 | nohup bash run.sh 后台启动 |
| 04 | runtop | docker ps 容器状态 | 检查 ShareMemory/Login/World/Server 进程与端口 |
| 05 | link | docker-compose exec 进容器 | 直接进入 /tlgame/tlbb 服务端目录（原生无容器） |
| 06 | swap | 容器内加 swap | 本机增加虚拟内存（/usr/swap/swapfile，默认 4G） |
| 07 | rebuild | 重建容器 | 重构本机环境（备份→重置数据库→还原→写配置） |
| 08 | remove | docker rm 容器 | 移除本机环境与命令（数据迁移保留） |
| 09 | setconfig | 重写容器配置 | 重写 /root/.gs/.env 端口/密码 + 改数据库密码 |
| 10 | change | 容器换端 | 本机备份换端（untar→reset→setini→runtlbb） |
| 11 | restart | docker restart | 本机重启数据库+服务端 |
| 12 | gsbak | 容器内定时备份 | crontab 定时 mysqldump + 版本备份 |
| 13 | upcmd | gitee 拉取最新命令 | 从环境包 cmd/ 重新部署命令到 /usr/local/bin |
| 14 | upgm | nginx 容器 + DBConfig.php | 生成 /tlgame/www/gm + DBConfig.php + 开启 GM 工具 |
| 15 | upow | nginx 容器站点 | 创建 /tlgame/www/ow 开服网站目录 |
| 16 | step | 容器内分步启动 | 解析 run.sh 分步启动进程 |
| 17 | gstl | 下载镜像 compose up | 检测环境 → 显示配置(curgs) + 虚拟内存(swap) 提示 |
| 18 | backup | docker exec mysqldump | 本机 mysqldump（0=全部 1=版本 2=数据库） |
| 19 | close | docker stop | 本机关服 |
| 20 | gslog | docker logs | 本机日志（billing/ShareMemory/Login/World/Lua/debug/error） |
| 21 | rmlog | 容器内删除日志 | 本机删除日志 |
| 22 | curgs | docker inspect | 读取 /root/.gs/.env + 显示环境配置 |
| 23 | setpoint | docker exec SQL | 本机 mysql 执行 SQL（默认值/离线充值） |
| 24 | reset | docker exec 删库重导 | 本机 drop/create + 导入初始 SQL |
| 25 | setvalid | docker exec SQL | 本机 mysql 执行 SQL（封号/解封） |
| 26 | restore | docker exec mysql | 本机 mysql 导入 |
| 27 | delbak | 容器内删除备份 | 本机删除备份（默认保留 10 份） |
| 28 | gsfix | 重装 docker + 环境 | 修复本机组件/命令/数据库/ODBC |
| 29 | logbak | 容器内定时日志备份 | crontab 定时备份日志 |
| - | color | 容器内颜色库 | /usr/local/bin/color 公共库 |
| - | gs | 帮助菜单 | 同款帮助菜单（gs / gs 01 / gs untar） |
| - | gsctl | - | 统一命令入口（gsctl <命令> [参数...]，替代原 tl_* 前缀） |

## 环境配置（/root/.gs/.env，变量名对齐 gstlenv env.sample）

| 配置项 | 默认值 | 说明 |
|---|---|---|
| VERSION | v2.8.28 | 版本号（与 gstlenv 一致） |
| TLBB_PATH | /tlgame/tlbb | 服务端根目录 |
| BACKUP_DIR | /tlgame/backup | 备份目录 |
| BILLING_PORT | 21818 | Billing 验证端口 |
| TL_MYSQL_PORT | 3306 | MySQL 监听端口（gstlenv 对外映射 33061 收敛为本机 3306） |
| LOGIN_PORT | 13580 | 登录网关端口 |
| SERVER_PORT | 15680 | 游戏网关端口 |
| WEB_PORT | 51888 | 网站端口 |
| WEB_GM_PORT | 61888 | GM 网站端口 |
| TL_MYSQL_PASSWORD | 123456 | 数据库 root 密码 |
| LOGIN_USER_NAME / LOGIN_PASSWORD | gsgameshare / gsgameshare.com | GM 工具登录账号 |
| PRIVATE_KEY | Gsgameshare.com2025 | GM 通信私钥 |
| REDIS_PASSWORD | gsgameshare.com | Redis 密码（预留） |

## 安装内容明细

| 组件 | 说明 | 离线 |
|---|---|---|
| MySQL 5.1/5.7/8.0 | el5/6/7 离线 MySQL 5.1；el8 MySQL 5.7；el9/10+8.0；Ubuntu 20+/Debian 8.0（不用 MariaDB） | el6/7 ✅（5.7/8.0 走 pack_offline 生成） |
| unixODBC | ODBC 管理器（el5/6/7 离线 rpm；el8+/deb 走源或源码） | el5/6/7 ✅ |
| MySQL ODBC 3.51 驱动 | 32 位 libmyodbc3（服务端必须） | ✅ |
| MySQL ODBC 5.1 驱动 | 64 位 libmyodbc5（el7+ 管理工具用） | ✅ |
| glibc.i686 等 32 位兼容库 | 服务端为 32 位进程，必须 | 走系统源 |
| tlbbdb.sql / web.sql | 游戏库表结构 | ✅ |
| odbc.ini / odbcinst.ini | 自动生成 | ✅ |

## 离线包管理（不进 git 版本管理）

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

### 方式三：镜像网站直下离线包（无对应系统 VM 时）

不想准备对应发行版的联网机器时，可直接用内置下载脚本从**国内镜像网站**抓取
MySQL 离线包到本地 `offline/`（脚本按发行版分支自动选择镜像：阿里云 > 腾讯 > 华为 > 清华）：

```bash
bash scripts/download_offline.sh el8 80      # el8 + MySQL 8.0 (阿里云 centos-vault AppStream)
bash scripts/download_offline.sh el7 57      # el7 + MySQL 5.7 (官方直链, 已 EOL 镜像下架兜底)
bash scripts/download_offline.sh el7 51      # el7 + MySQL 5.1 (已内置, 提示跳过)
bash scripts/download_offline.sh el6 51      # el6 + MySQL 5.1 (阿里云 centos-vault)
bash scripts/download_offline.sh el5 51      # el5 + MySQL 5.1 (阿里云 centos-vault)
bash scripts/download_offline.sh ubuntu24 80 # Ubuntu 24.04 + MySQL 8.0 deb (清华/阿里云 ubuntu 主源)
bash scripts/download_offline.sh debian12 80 # Debian 12: 官方已无 mysql-server (MariaDB 取代), 需 mysql-community
```

> 说明：
> - **不同发行版必须使用不同安装包**（rpm/deb 格式、glibc、依赖链完全不同），无法跨发行版混用。
> - el5/6/8 已 EOL，官方源下线 → 走 `centos-vault` 历史存档镜像；MySQL 5.7 官方仓库 2023-10 下线，
>   脚本自动回退 `dev.mysql.com` 官方文件直链（已验证 5.7.44 全套 6 包可下）。
> - 下载后执行 `bash scripts/pack_offline.sh` 重新打包即可分发到无网机。

> 说明：仓库 clone 后需先通过 `pack_offline.sh` 重新生成 offline/（或直接从 `offline-packs/` 解压），再执行安装。

## 目录结构

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
├── cmd/                     ★ gs 原命令名全局管理命令（参考 gstlenv，反 Docker 化）
│   ├── gsctl.sh             统一命令入口（gsctl <命令> [参数...]）
│   ├── gs.sh                帮助菜单（gs / gs 01 / gs untar）
│   ├── untar.sh / setini.sh / runtlbb.sh / runtop.sh
│   ├── close.sh / restart.sh / swap.sh
│   ├── backup.sh / restore.sh / reset.sh / delbak.sh / logbak.sh
│   ├── setvalid.sh / setpoint.sh / curgs.sh
│   ├── change.sh / rebuild.sh / remove.sh
│   └── gslog.sh / rmlog.sh / step.sh / gstl.sh / upgm.sh / upow.sh / gsfix.sh / transfer.sh
├── scripts/                 版本一键脚本（ubuntu.sh / debian.sh 等）
└── docs/                    文档
    ├── 安装说明.md
    ├── 环境创建说明.md
    └── 注意事项.md
```

## 文档导航

- [安装说明](docs/安装说明.md) — 系统要求、安装前准备、安装步骤、验证
- [环境创建说明](docs/环境创建说明.md) — 从零到开服的完整流程
- [注意事项](docs/注意事项.md) — 端口/防火墙/安全/常见问题

---

*源码开发 · 非 Docker · 国内源优先 · 离线兜底 · 命令体系与 gstlenv 完全一致（v2.8.28）*