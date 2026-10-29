#!/bin/bash
# ============================================================
# TLBB 万能环境安装包 - 系统识别模块 (detect.sh)
# 识别所有主流发行版与版本, 映射到安装家族:
#   rhel6 | rhel7 | rhel8 | rhel9 | rhel10 | ubuntu | debian
# ============================================================

# 全局检测结果 (供调用方读取)
SYS_FAMILY=""        # rhel | debian | other
SYS_BRANCH=""        # el6|el7|el8|el9|el10|ubuntu|debian
SYS_ID=""            # centos/alinux/tencentos/openeuler/ubuntu/debian...
SYS_VERSION_ID=""    # 7.9 / 24.04 / 12 ...
SYS_CODENAME=""      # bionic/jammy/bookworm...
SYS_ARCH=""          # x86_64/aarch64...
SYS_PRETTY=""        # 人类可读名称
SYS_IS_CLOUD=""      # 云厂商标识: aliyun/tencent/huawei/baidu/generic
SYS_RELEASE_FILE=""  # /etc/redhat-release 原文

# ---------- 读取 /etc/os-release ----------
load_os_release() {
    local k v
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        v=${v#\"}; v=${v%\"}   # 去引号
        case "$k" in
            ID)            SYS_ID="$v";;
            VERSION_ID)    SYS_VERSION_ID="$v";;
            VERSION_CODENAME) SYS_CODENAME="$v";;
            PRETTY_NAME)   SYS_PRETTY="$v";;
        esac
    done < /etc/os-release
}

detect_system() {
    SYS_ARCH=$(uname -m 2>/dev/null || echo unknown)
    load_os_release   # 先读取 os-release 拿到 VERSION_ID / CODENAME
    # 1. 优先 RHEL 系 (redhat-release 最可靠, 兼容老系统)
    if [ -f /etc/redhat-release ]; then
        SYS_RELEASE_FILE=$(cat /etc/redhat-release 2>/dev/null)
        SYS_PRETTY="$SYS_RELEASE_FILE"
        local rel
        rel=$(echo "$SYS_RELEASE_FILE" | tr 'A-Z' 'a-z')
        # 云厂商 RHEL 兼容系统识别 (注意: almalinux 含子串 alinux, 必须先匹配)
        case "$rel" in
            *"almalinux"*)  SYS_ID="almalinux";;
            *"alinux"*)     SYS_ID="alinux";;
            *"aliyun"*)     SYS_ID="alinux";;      # Alinux 2 release 文案为 "Aliyun Linux"
            *"alibaba"*)    SYS_ID="alinux";;      # Alinux 3/4 release 文案为 "Alibaba Cloud Linux"
            *"anolis"*)     SYS_ID="anolis";;
            *"tencentos"*)  SYS_ID="tencentos";;
            *"tlinux"*)     SYS_ID="tencentos";;
            *"openeuler"*)  SYS_ID="openeuler";;
            *"euleros"*)    SYS_ID="euler";;
            *"rocky"*)      SYS_ID="rocky";;
            *"oracle"*)     SYS_ID="oracle";;
            *"red hat"*)    SYS_ID="redhat";;
            *"centos"*)     SYS_ID="centos";;
            *)              SYS_ID="centos";;  # 兜底按 centos
        esac
        SYS_FAMILY="rhel"
        # 提取大版本号
        if [ -n "$SYS_VERSION_ID" ]; then
            SYS_BRANCH="el${SYS_VERSION_ID%%.*}"
        else
            # 从 redhat-release 提取, 如 "CentOS Linux release 7.9.2009"
            local vn
            vn=$(echo "$SYS_RELEASE_FILE" | grep -oE '[0-9]+\.[0-9]+' | head -1)
            [ -z "$vn" ] && vn=$(echo "$SYS_RELEASE_FILE" | grep -oE 'release [0-9]+' | grep -oE '[0-9]+' | head -1)
            SYS_VERSION_ID="$vn"
            SYS_BRANCH="el${vn%%.*}"
        fi
        # 特殊: openEuler 版本映射 (20.03/22.03 -> el8 风格; 24.03+ -> el9 风格)
        if [ "$SYS_ID" = "openeuler" ]; then
            local ov="${SYS_VERSION_ID%%.*}"
            if [ "$ov" -le 22 ] 2>/dev/null; then SYS_BRANCH="el8"; else SYS_BRANCH="el9"; fi
        fi
        # 特殊: Alinux 2 = el7, 3 = el8, 4 = el9
        if [ "$SYS_ID" = "alinux" ]; then
            case "$SYS_VERSION_ID" in
                2*) SYS_BRANCH="el7";; 3*) SYS_BRANCH="el8";; 4*) SYS_BRANCH="el9";;
            esac
        fi
        # 特殊: TencentOS 2 = el7, 3 = el8, 4 = el9
        if [ "$SYS_ID" = "tencentos" ]; then
            case "$SYS_VERSION_ID" in
                2*) SYS_BRANCH="el7";; 3*) SYS_BRANCH="el8";; 4*) SYS_BRANCH="el9";;
            esac
        fi
        # 特殊: Anolis 8 = el8, 23 = el9
        if [ "$SYS_ID" = "anolis" ]; then
            case "$SYS_VERSION_ID" in
                8*) SYS_BRANCH="el8";; 23*) SYS_BRANCH="el9";;
            esac
        fi
        # 特殊: EulerOS 2.x = el7 风格
        if [ "$SYS_ID" = "euler" ]; then SYS_BRANCH="el7"; fi
        return 0
    fi

    # 2. Debian 系
    if [ -f /etc/debian_version ]; then
        SYS_FAMILY="debian"
        if [ -z "$SYS_ID" ] || [ "$SYS_ID" = "debian" ]; then SYS_ID="debian"; fi
        if [ -z "$SYS_ID" ]; then SYS_ID="debian"; fi
        # ubuntu / debian 由 os-release ID 决定
        SYS_BRANCH="debian"
        if [ "$SYS_ID" = "ubuntu" ]; then SYS_BRANCH="ubuntu"; fi
        return 0
    fi

    # 3. Fedora (无 redhat-release / debian_version, os-release ID=fedora 或存在 fedora-release)
    if [ "$SYS_ID" = "fedora" ] || [ -f /etc/fedora-release ]; then
        SYS_FAMILY="fedora"
        SYS_ID="fedora"
        [ -z "$SYS_VERSION_ID" ] && SYS_VERSION_ID=$(cat /etc/fedora-release | grep -oE '[0-9]+' | head -1)
        SYS_BRANCH="fedora"
        SYS_PRETTY="${SYS_PRETTY:-Fedora Linux $SYS_VERSION_ID}"
        return 0
    fi

    SYS_FAMILY="other"
    return 1
}

# ---------- 云厂商判定 ----------
# 通过 /etc/cloud 或系统信息粗略判定 (仅供参考, 不阻断安装)
detect_cloud() {
    SYS_IS_CLOUD="generic"
    if grep -qi aliyun /etc/cloud/cloud.cfg /etc/motd 2>/dev/null; then SYS_IS_CLOUD="aliyun"; fi
    if grep -qi tencent /etc/cloud/cloud.cfg /etc/motd 2>/dev/null; then SYS_IS_CLOUD="tencent"; fi
    if grep -qi huawei /etc/cloud/cloud.cfg /etc/motd 2>/dev/null; then SYS_IS_CLOUD="huawei"; fi
    if grep -qi baidu /etc/cloud/cloud.cfg /etc/motd 2>/dev/null; then SYS_IS_CLOUD="baidu"; fi
}

print_sysinfo() {
    info "=============================================="
    info "系统: $SYS_PRETTY"
    info "发行版ID: $SYS_ID | 版本: $SYS_VERSION_ID | 代号: $SYS_CODENAME"
    info "架构: $SYS_ARCH | 家族: $SYS_FAMILY | 分支: $SYS_BRANCH"
    info "云厂商: $SYS_IS_CLOUD"
    info "=============================================="
}
