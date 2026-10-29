#!/bin/bash
# ============================================================
# download_offline.sh - 离线包镜像站下载工具
# ------------------------------------------------------------
# 用途: 在没有对应系统 VM 的情况下, 直接从各镜像网站下载
#       MySQL 服务端及关键依赖 rpm/deb 到 offline/ 对应目录,
#       生成可按发行版版本分发的离线数据包 (不入 git)
# ------------------------------------------------------------
# 原理:
#   1) RHEL 系: 用 yum/dnf 仓库的 repodata (primary.xml.gz) 解析
#      mysql 核心包名 -> 直下 rpm; 镜像优先级: 阿里云 > 腾讯 > 华为
#   2) Debian 系: 用 Packages.gz 解析 mysql-server 包名 -> 直下 deb
#      镜像: 清华 tuna > 阿里云 > 华为 (老版本用 old-releases)
# ------------------------------------------------------------
# 用法:
#   bash scripts/download_offline.sh el8 mysql80    # el8 + MySQL 8.0
#   bash scripts/download_offline.sh el7 mysql57    # el7 + MySQL 5.7
#   bash scripts/download_offline.sh el7 mysql51    # el7 + MySQL 5.1
#   bash scripts/download_offline.sh el6 mysql51    # el6 + MySQL 5.1
#   bash scripts/download_offline.sh el5 mysql51    # el5 + MySQL 5.1
#   bash scripts/download_offline.sh ubuntu24 mysql80   # Ubuntu 24.04 + MySQL 8.0
#   bash scripts/download_offline.sh debian12 mysql80    # Debian 12 + MySQL 8.0
# 下载完成后: bash scripts/pack_offline.sh 重新打包 offline-packs/
# ------------------------------------------------------------
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# 允许环境变量覆盖包根目录 (脚本可独立拷贝到任意目录使用)
PKG_ROOT="${TLBB_PKG_ROOT:-$(dirname "$SCRIPT_DIR")}"
OFFLINE="$PKG_ROOT/offline"
TMP="/tmp/tlbb-dl"
mkdir -p "$TMP" "$OFFLINE"

log()  { echo -e "\033[32m[下载] $*\033[0m"; }
warn() { echo -e "\033[33m[警告] $*\033[0m"; }
die()  { echo -e "\033[31m[错误] $*\033[0m"; exit 1; }

# ---------- 解析仓库 primary.xml(.gz/.zst) 获取 rpm 列表 ----------
# $1=repo baseurl, $2=包名过滤关键字(以|分隔)
fetch_rpm_from_repo() {
    local baseurl="$1" filter="$2" outdir="$3"
    local repomd primary
    repomd=$(curl -fsSL --connect-timeout 15 --max-time 60 "${baseurl}/repodata/repomd.xml" 2>/dev/null) || return 1
    primary=$(echo "$repomd" | grep -oE '<location href="repodata/[^"]*primary[^"]*\.(gz|zst)"' | head -1 | sed 's/.*href="//;s/"$//')
    [ -z "$primary" ] && return 1
    curl -fsSL --connect-timeout 15 --max-time 120 "${baseurl}/${primary}" -o "$TMP/primary.xml.gz" 2>/dev/null || return 1
    local files
    case "$primary" in
        *.zst)
            local dec=""
            if command -v zstd >/dev/null 2>&1; then
                zstd -d -f "$TMP/primary.xml.gz" -o "$TMP/primary.xml" 2>/dev/null && dec=1
            else
                python3 -c "import zstandard,sys; zstandard.ZstdDecompressor().copy_stream(open('$TMP/primary.xml.gz','rb'), open('$TMP/primary.xml','wb'))" 2>/dev/null && dec=1
            fi
            [ -z "$dec" ] && return 1
            files=$(grep -oE '<location href="[^"]*\.rpm"' "$TMP/primary.xml" 2>/dev/null | sed 's/<location href="//;s/".*//' | \
                grep -E "$filter" | grep -vE 'debuginfo|devel|test|benchmark|embedded|connector-java' | sort -u)
            ;;
        *)
            files=$(zcat "$TMP/primary.xml.gz" 2>/dev/null | grep -oE '<location href="[^"]*\.rpm"' | sed 's/<location href="//;s/".*//' | \
                grep -E "$filter" | grep -vE 'debuginfo|devel|test|benchmark|embedded|connector-java' | sort -u)
            ;;
    esac
    [ -z "$files" ] && return 1
    local n=0
    for f in $files; do
        local fn; fn=$(basename "$f")
        [ -f "${outdir}/${fn}" ] && continue        # 已存在跳过 (幂等)
        curl -fsSL --connect-timeout 15 --max-time 300 "${baseurl}/${f}" -o "${outdir}/${fn}" 2>/dev/null && n=$((n + 1))
    done
    echo "$n"
}

# ---------- 下载 RHEL 系离线包 ----------
dl_rhel() {
    local branch="$1" mver="$2"   # el5|el6|el7|el8|el9, 51|57|80
    local outdir="$OFFLINE/rpm-packages/${branch}/mysql${mver}"
    mkdir -p "$outdir"
    case "$branch" in
        el5)  # CentOS 5.11 vault (阿里云: repomd 在 os/x86_64 层级)
            local base="https://mirrors.aliyun.com/centos-vault/5.11/os/x86_64"
            local n
            n=$(fetch_rpm_from_repo "$base" "mysql-" "$outdir") && \
                log "el5 MySQL 5.1 rpm 下载 ${n} 个到 $outdir" || warn "el5 镜像解析失败, 可手工从 vault 下载"
            ;;
        el6)  # CentOS 6.10 vault
            local base="https://mirrors.aliyun.com/centos-vault/6.10/os/x86_64"
            local n
            n=$(fetch_rpm_from_repo "$base" "mysql-" "$outdir") && \
                log "el6 MySQL 5.1 rpm 下载 ${n} 个到 $outdir" || warn "el6 镜像解析失败"
            ;;
        el7)
            if [ "$mver" = "51" ]; then
                # MySQL 5.1: 已有内置 MySQL.tar.gz (mysql-client/server 5.1), 仅提示
                log "el7 MySQL 5.1 已内置 (offline/el7/MySQL.tar.gz), 无需下载"
                return 0
            elif [ "$mver" = "57" ]; then
                # MySQL 5.7: mysql57-community 仓库已 EOL (2023-10), 国内镜像已下架
                # 兜底方案: MySQL 官方 Downloads 目录文件直链 (目录页 404 但文件可下)
                local direct_urls=(
                    "https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-community-server-5.7.44-1.el7.x86_64.rpm"
                    "https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-community-client-5.7.44-1.el7.x86_64.rpm"
                    "https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-community-libs-5.7.44-1.el7.x86_64.rpm"
                    "https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-community-libs-compat-5.7.44-1.el7.x86_64.rpm"
                    "https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-community-common-5.7.44-1.el7.x86_64.rpm"
                    "https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-community-embedded-compat-5.7.44-1.el7.x86_64.rpm"
                )
                local n=0
                for u in "${direct_urls[@]}"; do
                    curl -fsSL --connect-timeout 15 --max-time 300 "$u" -o "${outdir}/$(basename "$u")" 2>/dev/null && n=$((n + 1))
                done
                [ "$n" -gt 0 ] && log "el7 MySQL 5.7.44 官方直链下载 ${n} 个到 $outdir" || {
                    warn "官方直链失败, 尝试镜像仓库..."
                    local bases=(
                        "https://mirrors.aliyun.com/mysql/yum/mysql57-community/el/7/x86_64"
                        "https://mirrors.cloud.tencent.com/mysql/yum/mysql57-community/el/7/x86_64"
                        "https://repo.huaweicloud.com/mysql/yum/mysql57-community/el/7/x86_64"
                        "https://repo.mysql.com/yum/mysql57-community/el/7/x86_64"
                    )
                    for b in "${bases[@]}"; do
                        n=$(fetch_rpm_from_repo "$b" "mysql-community-(server|client|libs|common|client-plugins)" "$outdir") && break
                        warn "镜像不可用: $b, 尝试下一个"
                    done
                    [ "$n" -gt 0 ] && log "el7 MySQL 5.7 rpm 下载 ${n} 个到 $outdir" || warn "el7 mysql57 全部镜像失败"
                }
            else
                die "el7 只支持 51/57 (8.0 无官方 el7 包)"
            fi
            ;;
        el8|el9|el10)
            # MySQL 8.0: 发行版 AppStream (el8 已 EOL 走 vault)
            local bases=()
            case "$branch" in
                el8)  bases+=("https://mirrors.aliyun.com/centos-vault/8-stream/AppStream/x86_64/os" "https://mirrors.aliyun.com/centos-vault/8.5.2111/AppStream/x86_64/os");;
                el9)  bases+=("https://mirrors.aliyun.com/centos-stream/9-stream/AppStream/x86_64/os");;
                el10) bases+=("https://mirrors.aliyun.com/centos-stream/10-stream/AppStream/x86_64/os");;
            esac
            local n=""
            local mf
            [ "$branch" = "el10" ] && mf="(mysql8\.4|mysql-selinux)-" || mf="mysql-"
            for b in "${bases[@]}"; do
                n=$(fetch_rpm_from_repo "$b" "$mf" "$outdir") && break
                warn "镜像不可用: $b, 尝试下一个"
            done
            [ -n "$n" ] && log "${branch} MySQL 8.0 rpm 下载 ${n} 个到 $outdir" || warn "${branch} 全部镜像失败"
            ;;
    esac
}

# ---------- minimal 完整集: compat(32位库) + odbc + redis (mysql 走 dl_rhel) ----------
dl_rhel_full() {
    local branch="$1"
    local base_os="" base_app=""
    case "$branch" in
        el5)  base_os="https://mirrors.aliyun.com/centos-vault/5.11/os/x86_64" ;;
        el6)  base_os="https://mirrors.aliyun.com/centos-vault/6.10/os/x86_64" ;;
        el7)  base_os="https://mirrors.aliyun.com/centos-vault/7.9.2009/os/x86_64"; base_app="https://mirrors.aliyun.com/centos-vault/7.9.2009/AppStream/x86_64/os" ;;
        el8)  base_os="https://mirrors.aliyun.com/centos-vault/8-stream/BaseOS/x86_64/os"; base_app="https://mirrors.aliyun.com/centos-vault/8-stream/AppStream/x86_64/os" ;;
        el9)  base_os="https://mirrors.aliyun.com/centos-stream/9-stream/BaseOS/x86_64/os"; base_app="https://mirrors.aliyun.com/centos-stream/9-stream/AppStream/x86_64/os" ;;
        el10) base_os="https://mirrors.aliyun.com/centos-stream/10-stream/BaseOS/x86_64/os"; base_app="https://mirrors.aliyun.com/centos-stream/10-stream/AppStream/x86_64/os" ;;
        *) warn "不支持的版本: $branch"; return 1;;
    esac
    local compat_out="$OFFLINE/rpm-packages/${branch}/compat"
    local odbc_out="$OFFLINE/rpm-packages/${branch}/odbc"
    local redis_out="$OFFLINE/rpm-packages/${branch}/redis"
    mkdir -p "$compat_out" "$odbc_out" "$redis_out"
    # 32位兼容库 (TLBB 端依赖) - 包名带版本号: glibc-2.12-...i686.rpm
    local compat_filter='(glibc|libstdc\+\+|zlib|ncurses-libs|libnsl|libxcrypt|libgcc|libaio|openssl|libcurl|libxml2)-[^"]*\.i686\.rpm'
    local odbc_filter='(unixODBC|mysql-connector-odbc|mariadb-connector-odbc)(-|[0-9.])'
    local redis_filter='redis-[0-9]'
    for src in "$base_os" "$base_app"; do
        [ -z "$src" ] && continue
        fetch_rpm_from_repo "$src" "$compat_filter" "$compat_out" >/dev/null 2>&1 || true
        fetch_rpm_from_repo "$src" "$odbc_filter" "$odbc_out" >/dev/null 2>&1 || true
        if [ "$branch" != "el5" ] && [ "$branch" != "el6" ]; then
            fetch_rpm_from_repo "$src" "$redis_filter" "$redis_out" >/dev/null 2>&1 || true
        fi
    done
    local c o r
    c=$(ls "$compat_out" 2>/dev/null | wc -l); o=$(ls "$odbc_out" 2>/dev/null | wc -l); r=$(ls "$redis_out" 2>/dev/null | wc -l)
    log "「${branch}」minimal 完整集: compat=${c} odbc=${o} redis=${r}"
    [ "$branch" = "el5" ] && warn "el5 官方无 redis 包, 需源码编译 (可跳过, billing 在 el5 场景可选)"
}

# ---------- 下载 Debian 系离线包 ----------
# $1=镜像repo根(baseurl), $2=二进制索引相对路径(如 dists/bookworm/main/binary-amd64/Packages.gz)
#    $3=包名, $4=输出目录
fetch_deb() {
    local baseurl="$1" indexrel="$2" pkg="$3" outdir="$4"
    curl -fsSL --connect-timeout 15 --max-time 120 "${baseurl}/${indexrel}" -o "$TMP/Packages.gz" 2>/dev/null || return 1
    local fname
    fname=$(zcat "$TMP/Packages.gz" 2>/dev/null | awk -v p="$pkg" '$1=="Package:" && $2==p {f=1} f && $1=="Filename:" {print $2; exit}')
    [ -z "$fname" ] && return 1
    curl -fsSL --connect-timeout 15 --max-time 300 "${baseurl}/${fname}" -o "$outdir/$(basename "$fname")" 2>/dev/null && echo "OK" || return 1
}

dl_debian() {
    local target="$1"
    local outdir="$OFFLINE/deb-packages/$target"
    mkdir -p "$outdir"
    case "$target" in
        ubuntu24)  dl_ubuntu_deb "noble" "$outdir" ;;
        ubuntu22)  dl_ubuntu_deb "jammy" "$outdir" ;;
        ubuntu20)  dl_ubuntu_deb "focal" "$outdir" ;;
        ubuntu18)  dl_ubuntu_deb "bionic" "$outdir" ;;
        debian12)  dl_debian_deb "bookworm" "$outdir" ;;
        debian11)  dl_debian_deb "bullseye" "$outdir" ;;
        *) warn "不支持的 debian 目标: $target";;
    esac
}

# Ubuntu: Ubuntu 官方主源含真实 MySQL 8.0, 下载 minimal 完整集 (server+client+libs+odbc+redis)
dl_ubuntu_deb() {
    local codename="$1" outdir="$2"
    local bases=(
        "https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
        "https://mirrors.aliyun.com/ubuntu"
        "https://repo.huaweicloud.com/ubuntu"
    )
    # minimal 完整集: mysql 服务端/客户端/库 + unixODBC + redis
    local pkgs=(mysql-server-8.0 mysql-server-core-8.0 mysql-client-8.0 mysql-client-core-8.0
                libmysqlclient21 mysql-common libaio1 unixodbc redis-server)
    local got=""
    for b in "${bases[@]}"; do
        local n=0
        for p in "${pkgs[@]}"; do
            [ "$(fetch_deb "$b" "dists/${codename}/main/binary-amd64/Packages.gz" "$p" "$outdir")" = "OK" ] && n=$((n + 1))
        done
        if [ "$n" -gt 0 ]; then got=1; log "Ubuntu ${codename} 完整集 deb 下载 ${n} 个 (${b})"; break; fi
        warn "Ubuntu 镜像不可用: $b"
    done
    [ -z "$got" ] && warn "Ubuntu ${codename} 全部镜像失败, 建议在 Ubuntu 机器上执行 pack_offline.sh --full ubuntu${codename}"
}

# Debian 11/12: 官方源已移除 mysql-server (MariaDB 取代), 但 MySQL 官方 apt 仓库
# (repo.mysql.com/apt) 支持 bullseye/bookworm! 下载 mysql-community-* 全套,
# 其余依赖 (unixodbc/redis/libaio/i386 32位库) 从 Debian 官方镜像补齐
dl_debian_deb() {
    local codename="$1" outdir="$2"
    mkdir -p "$outdir"
    local n=0 got=""
    # 1) MySQL 官方 apt 仓库 (repo.mysql.com, 支持 Debian 11/12)
    #    注意: 其 Packages.gz 中 Filename 相对 /apt/ 根, baseurl 必须是 apt 根
    local mbase="https://repo.mysql.com/apt"
    local mindex="dists/${codename}/mysql-8.0/binary-amd64/Packages.gz"
    local mpkgs=(mysql-community-server mysql-community-server-core mysql-community-client
                 mysql-community-client-plugins mysql-community-libs mysql-community-libs-compat
                 mysql-community-common mysql-common)
    for p in "${mpkgs[@]}"; do
        [ "$(fetch_deb "$mbase" "$mindex" "$p" "$outdir")" = "OK" ] && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && { got=1; log "Debian ${codename} MySQL 8.0 官方 apt 下载 ${n} 个"; } \
                  || warn "Debian ${codename} MySQL 官方 apt 下载失败 (repo.mysql.com 可能不可达)"
    # 2) Debian 官方镜像: 辅助组件 + 32 位兼容库
    local dbases=(
        "https://mirrors.tuna.tsinghua.edu.cn/debian"
        "https://mirrors.aliyun.com/debian"
    )
    local amd64=("unixodbc" "redis-server" "libaio1" "libaio1t64")
    local i386=("libc6-i386" "libstdc++6" "libncurses6" "zlib1g" "libnsl2" "libaio1" "libaio1t64")
    for b in "${dbases[@]}"; do
        local n2=0 n3=0
        for p in "${amd64[@]}"; do
            [ "$(fetch_deb "$b" "dists/${codename}/main/binary-amd64/Packages.gz" "$p" "$outdir")" = "OK" ] && n2=$((n2 + 1))
        done
        for p in "${i386[@]}"; do
            # binary-i386 索引中同名包即 i386 架构 (无需 :i386 后缀)
            [ "$(fetch_deb "$b" "dists/${codename}/main/binary-i386/Packages.gz" "$p" "$outdir")" = "OK" ] && n3=$((n3 + 1))
        done
        if [ "$((n2 + n3))" -gt 0 ]; then got=1; log "Debian ${codename} 辅助组件 amd64=${n2} i386=${n3} (${b})"; break; fi
        warn "Debian 镜像不可用: $b"
    done
    [ -z "$got" ] && warn "Debian ${codename} 全部镜像失败"
}

# ---------- Fedora 离线包 (Fedora 34-38) ----------
# Fedora 无 MySQL 官方 yum 仓库 (默认 MariaDB), 方案:
#   1) MySQL 8.0 官方通用 Linux 二进制 tarball (glibc>=2.17 任意 x86_64 可跑)
#   2) 辅助组件从 Fedora archive 仓库下载 (用最低版本 F34 的 rpm, 依赖 >= 可覆盖 34->38)
dl_fedora() {
    local outdir="$OFFLINE/rpm-packages/fedora/mysql80"
    mkdir -p "$outdir"
    local tb="mysql-8.0.36-linux-glibc2.17-x86_64.tar.xz"
    local url
    for url in "https://cdn.mysql.com/Downloads/MySQL-8.0/${tb}" "https://dev.mysql.com/get/Downloads/MySQL-8.0/${tb}"; do
        if curl -fsSL --connect-timeout 15 --max-time 900 "$url" -o "$outdir/$tb" 2>/dev/null; then
            log "Fedora MySQL 8.0 通用二进制下载成功 ($(du -h "$outdir/$tb" | cut -f1))"
            return 0
        fi
        warn "下载失败: $url, 尝试下一个"
    done
    warn "Fedora MySQL 通用二进制下载失败, 请手工下载到 $outdir/"
}

dl_fedora_full() {
    local outdir="$OFFLINE/rpm-packages/fedora"
    local compat_out="$outdir/compat" odbc_out="$outdir/odbc" redis_out="$outdir/redis"
    mkdir -p "$compat_out" "$odbc_out" "$redis_out"
    # Fedora 34 archive (最低版本: rpm 依赖 >= 覆盖 34~38)
    local bases=(
        "https://archive.fedoraproject.org/pub/archive/fedora/linux/releases/34/Everything/x86_64/os"
        "https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/34/Everything/x86_64/os"
    )
    local compat_filter='(glibc|libstdc\+\+|zlib|ncurses-libs|libnsl|libxcrypt|libgcc|libaio|openssl)-[^"]*\.i686\.rpm'
    local odbc_filter='(unixODBC|mariadb-connector-odbc|mysql-connector-odbc)(-|[0-9.])'
    local redis_filter='redis-[0-9]'
    local got=""
    for b in "${bases[@]}"; do
        local c o r
        c=$(fetch_rpm_from_repo "$b" "$compat_filter" "$compat_out" 2>/dev/null || echo 0)
        o=$(fetch_rpm_from_repo "$b" "$odbc_filter" "$odbc_out" 2>/dev/null || echo 0)
        r=$(fetch_rpm_from_repo "$b" "$redis_filter" "$redis_out" 2>/dev/null || echo 0)
        if [ "$((c + o + r))" -gt 0 ]; then
            got=1
            log "Fedora(基于F34 archive, 覆盖34~38) 完整集: compat=${c} odbc=${o} redis=${r} (${b})"
            break
        fi
        warn "Fedora archive 不可用: $b"
    done
    [ -z "$got" ] && warn "Fedora archive 全部失败"
}

# ---------- 主入口 ----------
[ $# -lt 1 ] && { echo "用法: download_offline.sh [--full] <el5|el6|el7|el8|el9|el10|ubuntu18|ubuntu20|ubuntu22|ubuntu24|debian11|debian12|fedora34~38> [51|57|80]"; exit 1; }
FULL=""
[ "$1" = "--full" ] && { FULL=1; shift; }
MVER="${2:-auto}"; MVER="${MVER#mysql}"   # 兼容 mysql80/80 两种写法
case "$1" in
    el5|el6|el7|el8|el9|el10)
        if [ -n "$FULL" ]; then
            dl_rhel "$1" "$MVER"      # 1) mysql 服务端
            dl_rhel_full "$1"         # 2) compat + odbc + redis
        else
            dl_rhel "$1" "$MVER"
        fi
        ;;
    ubuntu*|debian*)     dl_debian "$1";;
    fedora*)
        dl_fedora                    # 1) mysql 通用二进制 tarball
        dl_fedora_full               # 2) compat + odbc + redis (F34 集覆盖 34~38)
        ;;
    *) warn "不支持的版本: $1"; exit 1;;
esac
log "下载完成. 重新打包: bash scripts/pack_offline.sh"
