#!/bin/bash
# ============================================================
# TLBB 万能环境安装包 - 公共函数库 (common.sh)
# 适用: CentOS 6/7/8/9/10 | Alinux | TencentOS | openEuler | EulerOS
#       Anolis | Ubuntu 12~24 | Debian 10~18 | 各类云厂商 Linux
# 说明: 本文件为函数库, 被 install.sh / 各版本脚本 source 使用
# ============================================================

# ---------- 全局常量 ----------
TLBB_INSTALL_DIR="/opt/tlbb-env"
TLBB_DB_USER="root"            # 数据库管理账号
TLBB_DB_PASS="${TLBB_DB_PASS:-123456}"   # 数据库密码(默认 123456, 对齐 gstlenv env.sample)
TLBB_OFFLINE_DIR=""            # 离线组件目录(自动定位)
TLBB_FORCE_ONLINE="0"          # 强制在线安装(跳过离线组件检测)
TLBB_MIRROR_PRIORITY="aliyun"  # 国内源优先级: aliyun|tencent|huawei|163|sohu|baidu
TLBB_NONINTERACTIVE="${TLBB_NONINTERACTIVE:-0}"  # 非交互模式(用环境变量 TLBB_DB_PASS)

# ============================================================
# gstlenv 默认值对齐 (参考 gstlenv-master/env.sample 与 docker-compose*.yml)
# 原生安装版将 docker 映射端口收敛为本机服务端口:
#   MySQL 本机 3306 (gstlenv 对外映射 33061)
#   服务端端口沿用 gstlenv 容器内端口: Login 13580 / Server 15680 / Billing 21818
# ============================================================
TLBB_MYSQL_VERSION="${TLBB_MYSQL_VERSION:-auto}"   # auto|51|57|80 (自动按系统选择)
TLBB_MYSQL_PORT="${TLBB_MYSQL_PORT:-3306}"         # 本机 MySQL 监听端口
TLBB_MYSQL_USER="${TLBB_MYSQL_USER:-gs}"           # 游戏数据库账号 (gstlenv: TL_MYSQL_USER=gs)
TLBB_MYSQL_PASSWORD="${TLBB_MYSQL_PASSWORD:-123456}" # 游戏账号密码 (gstlenv: TL_MYSQL_PASSWORD=123456)
TLBB_BILLING_PORT="${TLBB_BILLING_PORT:-21818}"    # billing 验证端口 (gstlenv: BILLING_PORT=21818)
TLBB_LOGIN_PORT="${TLBB_LOGIN_PORT:-13580}"        # 登录网关端口 (gstlenv: LOGIN_PORT=13580)
TLBB_SERVER_PORT="${TLBB_SERVER_PORT:-15680}"      # 游戏网关端口 (gstlenv: SERVER_PORT=15680)
TLBB_WEB_PORT="${TLBB_WEB_PORT:-51888}"            # web 访问端口 (gstlenv: WEB_PORT=51888)
TLBB_WEB_GM_PORT="${TLBB_WEB_GM_PORT:-61888}"      # web GM 端口 (gstlenv: WEB_GM_PORT=61888)
TLBB_TZ="${TLBB_TZ:-Asia/Shanghai}"                # 时区 (gstlenv: TZ=Asia/Shanghai)

# ---------- MySQL 版本选择 (对齐 gstlenv 环境编号体系) ----------
# gstlenv 编号: 1=CentOS6+MySQL5.1  2=CentOS7+MySQL5.1
#               3=CentOS7+MySQL5.7  4=CentOS9+MySQL8.0
# 输出: 51|57|80
select_mysql_version() {
    if [ -n "$TLBB_MYSQL_VERSION" ] && [ "$TLBB_MYSQL_VERSION" != "auto" ]; then
        echo "$TLBB_MYSQL_VERSION"; return 0
    fi
    case "$SYS_FAMILY:$SYS_BRANCH" in
        rhel:el5|rhel:el6)  echo "51";;   # 老 RHEL → MySQL 5.1
        rhel:el7)           echo "51";;   # el7 默认 5.1 (兼容老端), 可 TLBB_MYSQL_VERSION=57 指定
        rhel:el8)           echo "80";;   # el8: MySQL 5.7 无官方 el8 包, 只能 8.0
        rhel:el9|rhel:el10) echo "80";;   # 新系统 → MySQL 8.0
        debian:ubuntu)
            case "$SYS_VERSION_ID" in
                12*|13*|14*|15*|16*) echo "51";;  # Ubuntu 12-16 → 系统自带 MySQL 5.5/5.6
                18*)                echo "57";;   # Ubuntu 18 → 系统自带 MySQL 5.7
                *)                  echo "80";;   # Ubuntu 20+ → 系统自带 MySQL 8.0
            esac;;
        debian:debian)      echo "80";;   # Debian 10+ → MySQL 官方 apt 源 8.0
        *)                  echo "80";;
    esac
}

# ---------- 颜色/日志 ----------
C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'; C_NONE=$'\033[0m'

log()  { echo -e "${C_GREEN}[TLBB]${C_NONE} $*"; }
warn() { echo -e "${C_YELLOW}[警告]${C_NONE} $*"; }
err()  { echo -e "${C_RED}[错误]${C_NONE} $*"; }
info() { echo -e "${C_BLUE}[信息]${C_NONE} $*"; }

die()  { err "$*"; exit 1; }

# ---------- 品牌广告横幅 (GS游享网 · 天龙环境) ----------
brand_banner() {
    echo ""
    echo -e "${C_GREEN}============================================================${C_NONE}"
    echo -e "${C_GREEN}   GS游享网 · 天龙八部万能环境${C_NONE}"
    echo -e "${C_GREEN}   天龙八部怀旧/经典端环境一键部署 | 全网首发万能安装器${C_NONE}"
    echo -e "${C_GREEN}   本环境由 GS游享网 (gsgameshare.com) 出品并提供售后${C_NONE}"
    echo -e "${C_GREEN}   仅供学习研究使用, 请于下载后 24 小时内删除${C_NONE}"
    echo -e "${C_GREEN}============================================================${C_NONE}"
    echo ""
}

# ---------- 基础检查 ----------
check_root() {
    [ "$(id -u)" = "0" ] || die "必须以 root 权限运行本脚本 (请使用: sudo bash $0)"
}

check_arch() {
    local bit
    bit=$(getconf LONG_BIT 2>/dev/null || echo 64)
    if [ "$bit" != "64" ]; then
        err "检测到 ${bit} 位系统. TLBB 服务端环境仅支持 64 位系统(依赖 32 位兼容库)."
        err "注: 32 位系统请参考离线包中 ubuntu14_32bit 专用教程."
        exit 1
    fi
    log "系统位数: 64 位, 检查通过"
}

# ---------- 包管理器抽象 ----------
pkg_mgr() {
    if command -v dnf >/dev/null 2>&1; then echo "dnf";
    elif command -v yum >/dev/null 2>&1; then echo "yum";
    elif command -v apt-get >/dev/null 2>&1; then echo "apt";
    else echo "none"; fi
}

# 安装一组包 (自动选择包管理器)
pkg_install() {
    local mgr; mgr=$(pkg_mgr)
    case "$mgr" in
        yum|dnf) $mgr -y install "$@" >/dev/null 2>&1 || { warn "安装失败: $*"; return 1; };;
        apt)     DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" >/dev/null 2>&1 || { warn "安装失败: $*"; return 1; };;
        *)       die "未识别的包管理器";;
    esac
    return 0
}

# ---------- 离线组件定位 ----------
# 安装包可能位于 /opt /root /home 或与脚本同目录, 自动探测
locate_offline() {
    local cand="/opt/tlbb-env-pkg /opt /root /home $(dirname "$0")"
    local d
    for d in $cand; do
        if [ -d "$d/offline" ] && [ -d "$d/offline/sql" ]; then
            TLBB_OFFLINE_DIR="$d/offline"; return 0
        fi
        # 兼容直接解压/复制的情况
        if [ -d "$d" ] && [ -f "$d/tlbbdb.sql" ]; then
            TLBB_OFFLINE_DIR="$d"; return 0
        fi
    done
    return 1
}

# 从离线目录取文件 (可选路径, 找不到时按名查找)
off_get() {
    # $1 目录相对路径, $2 文件名
    local sub="$1"; local fname="$2"
    if [ -f "$TLBB_OFFLINE_DIR/$sub/$fname" ]; then
        echo "$TLBB_OFFLINE_DIR/$sub/$fname"; return 0
    fi
    local hit; hit=$(find "$TLBB_OFFLINE_DIR" -name "$fname" 2>/dev/null | head -1)
    [ -n "$hit" ] && { echo "$hit"; return 0; }
    return 1
}

# ---------- 数据库密码交互 ----------
ask_dbpass() {
    # 默认密码 123456 (对齐 gstlenv), 交互时可修改
    TLBB_DB_PASS="${TLBB_DB_PASS:-123456}"
    if [ "$TLBB_NONINTERACTIVE" = "1" ]; then
        [ -n "$TLBB_DB_PASS" ] || die "非交互模式需要提供环境变量 TLBB_DB_PASS"
        return
    fi
    if [ -z "${TLBB_DB_PASS_CONFIRMED:-}" ]; then
        read -p "数据库 root/gs 密码 (默认: ${TLBB_DB_PASS}, 直接回车使用默认): " p1
        [ -n "$p1" ] && TLBB_DB_PASS="$p1"
        if [ "${#TLBB_DB_PASS}" -lt 6 ]; then
            warn "密码长度至少 6 位, 使用默认值 ${TLBB_DB_PASS}"
        fi
        TLBB_DB_PASS_CONFIRMED=1
    fi
    export TLBB_DB_PASS
}

# ---------- 国内源可用性探测 ----------
# 返回第一个可用的镜像基础 URL
probe_mirror() {
    # $1: 镜像域名列表, $2: 探测路径
    local domains="$1"; local path="$2"
    local dom url code
    for dom in $domains; do
        url="https://$dom/$path"
        code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -A "Mozilla/5.0" "$url" 2>/dev/null)
        [ "$code" = "200" ] && { echo "$dom"; return 0; }
    done
    return 1
}
