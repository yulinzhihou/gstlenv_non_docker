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
TLBB_DB_PASS=""                # 数据库密码(交互输入)
TLBB_OFFLINE_DIR=""            # 离线组件目录(自动定位)
TLBB_FORCE_ONLINE="0"          # 强制在线安装(跳过离线组件检测)
TLBB_MIRROR_PRIORITY="aliyun"  # 国内源优先级: aliyun|tencent|huawei|163|sohu|baidu
TLBB_NONINTERACTIVE="0"        # 非交互模式(用环境变量 TLBB_DB_PASS)

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
    if [ -n "$TLBB_DB_PASS" ]; then return; fi
    if [ "$TLBB_NONINTERACTIVE" = "1" ]; then
        die "非交互模式需要提供环境变量 TLBB_DB_PASS"
    fi
    local p1=""
    while [ -z "$p1" ]; do
        read -s -p "请输入 MySQL/MariaDB root 密码 (>=8位): " p1; echo
        if [ "${#p1}" -lt 8 ]; then
            warn "密码长度必须 >= 8 位, 请重新输入"; p1=""
        fi
    done
    TLBB_DB_PASS="$p1"
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
