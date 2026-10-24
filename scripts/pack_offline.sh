#!/bin/bash
# ============================================================
# pack_offline.sh - 离线组件打包工具 (按发行版版本打包)
# ------------------------------------------------------------
# 用途:
#   1) 将 offline/ 下组件按发行版版本打包为独立 tar.gz
#      输出到 offline-packs/ (不进 git 版本管理)
#   2) 在联网机器上生成指定系统的完整离线包 (数据库+兼容库+驱动)
#      供无网络虚拟机/单机使用
# ------------------------------------------------------------
# 用法:
#   bash scripts/pack_offline.sh                    # 打包内置组件
#   bash scripts/pack_offline.sh --full el7         # 联网生成 el7 完整离线包
#   bash scripts/pack_offline.sh --full ubuntu24    # 联网生成 ubuntu24 完整离线包
#   bash scripts/pack_offline.sh install el7        # 从 offline-packs 解压 el7 离线包
# ============================================================
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

# ---------- 联网生成完整离线包 (数据库+兼容库+驱动) ----------
pack_full() {
    local target="$1"
    [ -z "$target" ] && { echo "用法: pack_offline.sh --full <el7|el8|el9|ubuntu20|ubuntu22|ubuntu24|debian12>"; exit 1; }
    local outdir="$OFFLINE/rpm-packages/$target"
    echo "===== 为 $target 生成完整离线包 ====="
    case "$target" in
        el7)
            outdir="$OFFLINE/rpm-packages/el7"
            mkdir -p "$outdir"
            # MySQL 5.1.73 已内置 (offline/el7), 这里补齐 unixODBC/glibc.i686 依赖
            command -v yumdownloader >/dev/null 2>&1 || yum -y install yum-utils >/dev/null 2>&1
            yumdownloader --resolve --destdir="$outdir" unixODBC unixODBC-devel unixODBC.i686 glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 libtool-ltdl 2>/dev/null
            echo "  el7 依赖已下载到 $outdir"
            ;;
        el8|el9)
            local m; m=$(command -v dnf >/dev/null && echo dnf || echo yum)
            command -v dnf download >/dev/null 2>&1 || command -v yumdownloader >/dev/null 2>&1 || $m -y install dnf-plugins-core >/dev/null 2>&1
            outdir="$OFFLINE/rpm-packages/${target}"
            mkdir -p "$outdir"
            $m download --resolve --destdir="$outdir" mariadb-server mariadb-client unixODBC unixODBC-devel glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 2>/dev/null
            echo "  ${target} 依赖已下载到 $outdir"
            ;;
        ubuntu20|ubuntu22|ubuntu24|debian11|debian12)
            outdir="$OFFLINE/deb-packages"
            mkdir -p "$outdir"
            # 以当前系统下载对应架构包 (建议在目标系统版本上执行)
            apt-get download mariadb-server mariadb-client unixodbc unixodbc-dev libodbc1:i386 libmyodbc 2>/dev/null \
                || apt-get download mariadb-server unixodbc libodbc1 2>/dev/null
            mv ./*.deb "$outdir/" 2>/dev/null
            echo "  deb 包已下载到 $outdir"
            ;;
        *)
            echo "不支持的版本: $target"; exit 1;;
    esac
    echo "完成后重新打包: bash scripts/pack_offline.sh"
}

# ---------- 从离线包安装到 offline/ ----------
pack_install() {
    local target="$1"
    [ -z "$target" ] && { echo "用法: pack_offline.sh install <el5|el6|el7|el8_9_10|deb|sql>"; exit 1; }
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
