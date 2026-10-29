#!/bin/bash
# ============================================================
# pack_offline.sh - 离线组件打包工具 (按发行版版本打包)
# ------------------------------------------------------------
# 用途:
#   1) 将 offline/ 下组件按发行版版本打包为独立 tar.gz
#      输出到 offline-packs/ (不进 git 版本管理)
#   2) 在联网机器上生成指定系统的完整离线包 (MySQL 5.1/5.7/8.0 + 兼容库+驱动)
#      供无网络虚拟机/单机使用
# ------------------------------------------------------------
# 用法:
#   bash scripts/pack_offline.sh                    # 打包内置组件
#   bash scripts/pack_offline.sh --full el7         # 联网生成 el7 完整离线包
#   bash scripts/pack_offline.sh --full el8 --mysql 57   # el8 指定 MySQL 5.7
#   bash scripts/pack_offline.sh --full ubuntu24    # 联网生成 ubuntu24 完整离线包
#   bash scripts/pack_offline.sh install el7        # 从 offline-packs 解压 el7 离线包
# ------------------------------------------------------------
# 数据库档位 (不用 MariaDB):
#   MySQL 5.1 -> el5/el6(yum) el7(内置 MySQL.tar.gz)
#   MySQL 5.7 -> el7/el8 (官方源: 阿里云/华为云镜像)
#   MySQL 8.0 -> el8/el9/el10 | Ubuntu 20+ | Debian 10+
# ------------------------------------------------------------
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_ROOT="$(dirname "$SCRIPT_DIR")"
OFFLINE="$PKG_ROOT/offline"
PACKS="$PKG_ROOT/offline-packs"
mkdir -p "$PACKS"

# ---------- 打包内置分区 ----------
pack_builtin() {
    echo "===== 打包内置离线组件 (offline/ 按版本) ====="
    declare -A MAP=(
        [el5]="el5"
        [el6]="el6"
        [el7]="el7"
        [el8_9_10]="el8_el9_el10"
        [deb]="deb-common"
        [sql]="sql"
        [el8]="rpm-packages/el8"
        [el9]="rpm-packages/el9"
        [el10]="rpm-packages/el10"
        [deb-mysql]="deb-packages"
    )
    for name in "${!MAP[@]}"; do
        local dir="$OFFLINE/${MAP[$name]}"
        [ -d "$dir" ] || continue
        local out="$PACKS/${name}-offline.tar.gz"
        tar czf "$out" -C "$OFFLINE" "${MAP[$name]}"
        echo "  [OK] $out ($(du -sh "$out" | cut -f1))"
    done
    echo "内置离线包已输出到 offline-packs/ (不入 git)"
}

# ---------- 联网生成完整离线包 (数据库+兼容库+驱动, 按 MySQL 版本分目录) ----------
pack_full() {
    local target="$1"
    [ -z "$target" ] && { echo "用法: pack_offline.sh --full <el6|el7|el8|el9|ubuntu18|ubuntu20|ubuntu22|ubuntu24|debian11|debian12> [--mysql 51|57|80]"; exit 1; }
    # 可选 --mysql 参数指定版本, 默认按系统自动
    local mver="auto"
    if [ "$2" = "--mysql" ] && [ -n "$3" ]; then mver="$3"; fi
    case "$target:$mver" in
        el6:*|el7:51|el7:auto) mver="51";;
        el8:*|el9:*)            [ "$mver" = "auto" ] && mver="57";;
        ubuntu18*)              mver="57";;
        ubuntu*)                mver="80";;
        debian*)                mver="80";;
    esac
    echo "===== 为 $target 生成 MySQL ${mver} 完整离线包 ====="
    case "$target" in
        el6)
            local outdir="$OFFLINE/rpm-packages/el6"
            mkdir -p "$outdir"
            command -v yumdownloader >/dev/null 2>&1 || yum -y install yum-utils >/dev/null 2>&1
            yumdownloader --resolve --destdir="$outdir" mysql-server mysql unixODBC unixODBC-devel unixODBC.i686 glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 libtool-ltdl 2>/dev/null
            echo "  el6 依赖已下载到 $outdir"
            ;;
        el7)
            # MySQL 5.1 已内置 (offline/el7/MySQL.tar.gz), 这里补齐 unixODBC/glibc.i686 依赖
            local outdir="$OFFLINE/rpm-packages/el7"
            mkdir -p "$outdir"
            command -v yumdownloader >/dev/null 2>&1 || yum -y install yum-utils >/dev/null 2>&1
            yumdownloader --resolve --destdir="$outdir" unixODBC unixODBC-devel unixODBC.i686 glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 libtool-ltdl 2>/dev/null
            echo "  el7 依赖已下载到 $outdir"
            ;;
        el8|el9)
            local m; m=$(command -v dnf >/dev/null && echo dnf || echo yum)
            command -v dnf download >/dev/null 2>&1 || command -v yumdownloader >/dev/null 2>&1 || $m -y install dnf-plugins-core >/dev/null 2>&1
            # 用发行版 AppStream 原生 mysql 包 (el8/el9 即 MySQL 8.0, 无需 mysql-community 官方源)
            # 若需官方 mysql-community 版本, 可先配置 mysql-community repo 后改用 mysql-community-server
            local outdir="$OFFLINE/rpm-packages/${target}/mysql${mver}"
            mkdir -p "$outdir"
            local dbpkg="mysql-server mysql mysql-libs mysql-common mysql-errmsg"
            $m download --resolve --destdir="$outdir" $dbpkg 2>/dev/null || \
                warn "dnf download 数据库包失败, 请确认 AppStream 源可用后重试"
            echo "  ${target} MySQL ${mver} 已下载到 $outdir"
            ;;
        ubuntu18)
            local outdir="$OFFLINE/deb-packages/mysql57"
            mkdir -p "$outdir"
            apt-get download mysql-server mysql-client libmysqlclient20 2>/dev/null
            mv ./*.deb "$outdir/" 2>/dev/null
            echo "  ubuntu18 MySQL 5.7 deb 已下载到 $outdir"
            ;;
        ubuntu*|debian*)
            local outdir="$OFFLINE/deb-packages/mysql80"
            mkdir -p "$outdir"
            apt-get download mysql-server mysql-client 2>/dev/null
            mv ./*.deb "$outdir/" 2>/dev/null
            echo "  ${target} MySQL 8.0 deb 已下载到 $outdir"
            ;;
        *)
            echo "不支持的版本: $target"; exit 1;;
    esac
    # 兼容库与 ODBC 驱动统一归入 common 目录
    case "$target" in
        el8|el9)
            mkdir -p "$OFFLINE/rpm-packages/${target}/compat"
            $m download --resolve --destdir="$OFFLINE/rpm-packages/${target}/compat" unixODBC unixODBC-devel glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 2>/dev/null || true
            ;;
    esac
    echo "完成后重新打包: bash scripts/pack_offline.sh"
}

# ---------- 从离线包安装到 offline/ ----------
pack_install() {
    local target="$1"
    [ -z "$target" ] && { echo "用法: pack_offline.sh install <el5|el6|el7|el8_9_10|deb|sql|rpm-packs>"; exit 1; }
    local f="$PACKS/${target}-offline.tar.gz"
    [ -f "$f" ] || { echo "未找到 $f"; exit 1; }
    tar zxf "$f" -C "$OFFLINE"
    echo "[OK] $target 离线包已解压到 offline/"
}

case "${1:-}" in
    --full)   pack_full "$2";;
    install)  pack_install "$2";;
    *)        pack_builtin;;
esac
