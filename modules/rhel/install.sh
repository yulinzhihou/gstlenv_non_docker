#!/bin/bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: RHEL 系安装模块 (el5~el10 及云厂商兼容系统, 配置 yum/dnf 源 + MySQL + ODBC)

# ============================================================
# TLBB 万能环境安装包 - RHEL 系安装模块 (modules/rhel/install.sh)
# 覆盖: el5/el6/el7/el8/el9/el10 及云厂商 RHEL 兼容系统
#   阿里云 Alinux 2(7)/3(8)/4(9) | Anolis 8/23
#   腾讯云 TencentOS 2(7)/3(8)/4(9)
#   华为 openEuler 20-22(8)/24+(9) | EulerOS 2.x(7)
#   百度云/主流云 CentOS 5~10
# ============================================================

# ---------- RHEL 分支判定包安装器 ----------
rhel_pkgmgr() {
    if command -v dnf >/dev/null 2>&1; then echo "dnf"; else echo "yum"; fi
}

rhel_pkg_install() {
    local m; m=$(rhel_pkgmgr)
    # --setopt=retries 缓解大 metadata 下载断流 (部分网络首次传输会超时)
    $m -y install --setopt=retries=4 --setopt=timeout=60 "$@" >/dev/null 2>&1 || { warn "包安装失败: $*"; return 1; }
}

# ---------- 切换国内源镜像 (各镜像路径结构一致, 仅替换域名) ----------
rhel_switch_repo_mirror() {
    # $1: tencent|huawei|tuna|ustc (aliyun 为默认首选, 不参与切换)
    local mir="$1" dom=""
    case "$mir" in
        tencent) dom="mirrors.cloud.tencent.com";;
        huawei)  dom="mirrors.huaweicloud.com";;
        tuna)    dom="mirrors.tuna.tsinghua.edu.cn";;
        ustc)    dom="mirrors.ustc.edu.cn";;
        *)       return 1;;
    esac
    # 匹配 "//域名" 以同时覆盖 http/https 前缀
    sed -i "s|//mirrors\.aliyun\.com|//${dom}|g; s|//mirrors\.cloud\.tencent\.com|//${dom}|g; s|//mirrors\.huaweicloud\.com|//${dom}|g; s|//mirrors\.tuna\.tsinghua\.edu\.cn|//${dom}|g; s|//mirrors\.ustc\.edu\.cn|//${dom}|g" /etc/yum.repos.d/tlbb.repo 2>/dev/null
    [ -s /etc/yum.repos.d/tlbb.repo ]
}

# ---------- 配置国内 yum/dnf 源 ----------
rhel_config_repo() {
    # 离线模式: 跳过源配置, 直接使用本地安装包 (传 force 则无视离线标志强制配置, 用于离线缺失时的在线回退)
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ] && [ "$1" != "force" ]; then
        log "离线模式: 跳过 yum/dnf 源配置, 使用本地 rpm 安装包"; return 0
    fi
    local repofile=""
    case "$SYS_ID:$SYS_BRANCH" in
        centos:el5)    repofile="centos5.repo";;
        centos:el6)    repofile="centos6.repo";;
        centos:el7)    repofile="centos7.repo";;
        centos:el8)    repofile="centos8.repo";;
        centos:el9)    repofile="centos9.repo";;
        centos:el10)   repofile="centos10.repo";;
        alinux:el7)    repofile="alinux2.repo";;
        alinux:el8)    repofile="alinux3.repo";;
        alinux:el9)    repofile="alinux3.repo";;
        anolis:el8)    repofile="anolis8.repo";;
        anolis:el9)    repofile="anolis8.repo";;   # Anolis23 结构近似, 需按实际探测
        tencentos:el7) repofile="tencentos2.repo";;
        tencentos:el8) repofile="tencentos3.repo";;
        tencentos:el9) repofile="tencentos4.repo";;
        openeuler:el8) repofile="openeuler22.repo";;
        openeuler:el9) repofile="openeuler24.repo";;
        euler:el7)     repofile="euler2.repo";;
        rocky:el8)     repofile="rocky8.repo";;
        rocky:el9)     repofile="rocky9.repo";;
        almalinux:*)   repofile="almalinux.repo";;
        *)             warn "未知系统组合 ${SYS_ID}:${SYS_BRANCH}, 跳过源替换(使用系统自带源)"; return 0;;
    esac

    local repo_src
    repo_src=$(find "$TLBB_OFFLINE_DIR/.." -name "$repofile" 2>/dev/null | head -1)
    [ -z "$repo_src" ] && repo_src=$(find /opt /root /home "$(dirname "$0")" -name "$repofile" 2>/dev/null | head -1)
    if [ -z "$repo_src" ]; then
        warn "未找到 $repofile, 将使用系统自带源 (可能因 EOL 失效)"
        return 0
    fi

    log "配置国内源: $repofile"
    mkdir -p /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null
    cp "$repo_src" /etc/yum.repos.d/tlbb.repo
    # 老版本 yum 需要清理插件缓存
    rm -f /etc/yum/pluginconf.d/fastestmirror.conf 2>/dev/null
    echo "timeout=120" >> /etc/yum.conf 2>/dev/null
    local m; m=$(rhel_pkgmgr)
    local retry_opt="--setopt=retries=4 --setopt=timeout=60"
    $m clean all >/dev/null 2>&1
    # makecache 失败自动换镜像重试 (部分网络对某镜像大 metadata 下载会超时/断流,
    # 小体积源正常而 BaseOS/AppStream 失败即此类问题, 实测各镜像 URL 均可达)
    local cacheok=0
    if $m makecache $retry_opt >/dev/null 2>&1; then
        cacheok=1
        log "国内源 makecache 完成"
    else
        warn "makecache 失败, 自动依次换用 腾讯云/华为云/中科大/清华 镜像重试..."
        for mir in tencent huawei ustc tuna; do
            rhel_switch_repo_mirror "$mir" || continue
            $m clean all >/dev/null 2>&1
            if $m makecache $retry_opt >/dev/null 2>&1; then
                log "已切换镜像源: $mir, makecache 完成"
                cacheok=1
                break
            fi
            warn "镜像源 $mir makecache 仍失败, 尝试下一个..."
        done
    fi
    [ "$cacheok" = "0" ] && warn "所有国内镜像 makecache 均失败, 请检查网络 (安装将继续, 部分组件可能失败)"
}

# ---------- 安装 32 位兼容库 ----------
rhel_install_compat() {
    log "安装 32 位兼容库 (glibc/libstdc++/libnsl/libcrypt)..."
    # 离线模式: 尝试本地 rpm 包目录 (offline/rpm-packages/<elX>/compat/ 或根目录), 否则仅提示
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
        # compat/ 子目录全部, 根目录仅匹配兼容库相关包 (避免误装 nginx/php/redis 等)
        local cdir=""; [ -d "$rdir/compat" ] && cdir="$rdir/compat"
        local rpms=""
        rpms=$(find "$rdir" -maxdepth 1 -name "*.rpm" 2>/dev/null | grep -E '(glibc|libstdc|libnsl|libcrypt|zlib|ncurses|libgcc|libaio|openssl|libcurl|libxml2)')
        [ -n "$cdir" ] && rpms="$rpms $(find "$cdir" -maxdepth 1 -name "*.rpm" 2>/dev/null)"
        if [ -n "$rpms" ]; then
            local installed=0 skipped=0 r
            for r in $rpms; do
                # 跳过系统核心库降级: 仅安装本机尚未安装的包
                local pkgname; pkgname=$(rpm -qp --qf '%{NAME}' "$r" 2>/dev/null)
                [ -z "$pkgname" ] && continue
                if rpm -q "$pkgname" >/dev/null 2>&1; then
                    skipped=$((skipped + 1)); continue
                fi
                rpm -ivh "$r" --nodeps --force >/dev/null 2>&1 && installed=$((installed + 1))
            done
            log "离线兼容库处理完成: 新装 ${installed} 个, 已存在跳过 ${skipped} 个 (来自 $rdir)"
        else
            # 离线缺失且网络可用时自动在线装 32 位兼容库 (dnf 并行装 i686 不降级 64 位)
            if curl -sI --connect-timeout 3 --max-time 5 https://mirrors.aliyun.com >/dev/null 2>&1; then
                log "离线未找到兼容库 rpm, 检测到网络可用, 自动回退在线源安装 32 位兼容库..."
                rhel_config_repo force >/dev/null 2>&1
                rhel_pkg_install glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 ncurses-libs.i686 libgcc.i686 2>/dev/null \
                    && log "32 位兼容库在线安装完成" \
                    || warn "32 位兼容库在线安装失败 (源不可用), 请手动 'yumdownloader --resolve glibc.i686' 补齐"
            else
                warn "离线模式未找到兼容库 rpm 且无网络, 32 位库可能缺失"
                warn "提示: 联网机器上 'yumdownloader --resolve glibc.i686' 等获取后放入该目录"
            fi
        fi
        return 0
    fi
    case "$SYS_BRANCH" in
        el5)
            rhel_pkg_install glibc.i686 libstdc++ libstdc++.i686 gcc
            ;;
        el6)
            rhel_pkg_install glibc.i686 libstdc++ libstdc++.i686 gcc
            ;;
        el7)
            rhel_pkg_install glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 gcc glibc-devel.i686
            # libstdc++.so.6 兜底 (EOL 后部分源缺少)
            yum -y install libstdc++.so.6 2>/dev/null || true
            # zlib i686 离线 rpm 兜底 (源失效时保证 32 位驱动可加载)
            local zlibrpm; zlibrpm=$(off_get el7/libmyodbc5-64bit zlib-1.2.7-19.el7_9.i686.rpm)
            [ -n "$zlibrpm" ] && rpm -ivh "$zlibrpm" --nodeps --force >/dev/null 2>&1 && log "zlib i686 离线兜底安装完成"
            ;;
        el8|el9|el10)
            local m; m=$(rhel_pkgmgr)
            # el9: 先启用 CRB 仓库 (32 位兼容库在 CRB 里)
            [ "$SYS_BRANCH" = "el9" ] && $m config-manager --set-enabled crb >/dev/null 2>&1 || true
            # 第一批: 完整 32 位兼容库
            $m -y install glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 gcc glibc-devel.i686 2>/dev/null || \
            # 第二批: 精简兜底 (部分源缺少 libnsl.i686/libcrypt.i686)
            $m -y install glibc.i686 libstdc++.i686 zlib.i686 2>/dev/null || \
            # 第三批: 仅最核心两个 (el9 AppStream 必须有)
            $m -y install glibc.i686 libstdc++.i686 2>/dev/null || warn "32 位库安装不完整, 请检查源"
            # 验证核心库是否装上
            if [ -f /usr/lib64/../lib/libc.so.6 ] || ls /lib/libc-*.so >/dev/null 2>&1; then
                log "32 位核心库 (glibc/libstdc++) 验证通过"
            else
                warn "32 位 glibc 未确认安装, 老端可能无法运行"
            fi
            ;;
    esac
    log "32 位兼容库安装完成"
}

# ---------- 配置 MySQL yum 源 (官方/国内镜像, 兼容嵌套与扁平目录) ----------
# 注意: 各版本官方包覆盖范围不同:
#   MySQL 5.7 官方仅 el6/el7 (无 el8+); MySQL 8.0 官方 el6/7/8/9 (无 el10);
#   MySQL 8.4 官方 el7/8/9/10 (el10 新系统首选 8.4).
# 目录结构: 官方 repo.mysql.com 为嵌套 mysql-8.4-community/el/10/x86_64,
#   国内镜像(清华 TUNA/腾讯云/阿里云) 为扁平 mysql-8.4-community-el10-x86_64,
#   探测时两种路径都试, 命中后按同风格写 repo (gpgcheck=0 便于内网/离线).
rhel_config_mysql_repo() {
    # $1: 51|57|80|84
    local ver="$1" rel="${SYS_BRANCH#el}"
    [ -z "$rel" ] && rel="7"
    # 防御: 版本在当前系统无官方包时自动切换
    if [ "$ver" = "57" ]; then
        case "$rel" in
            8|9)  warn "MySQL 5.7 无官方 el${rel} 包, 自动切换 MySQL 8.0"; ver="80";;
            10)   warn "MySQL 5.7 无官方 el${rel} 包, 自动切换 MySQL 8.4"; ver="84";;
        esac
    fi
    if [ "$ver" = "80" ] && [ "$rel" = "10" ]; then
        warn "MySQL 8.0 无官方 el10 包 (官方 8.0 仅提供 el6/7/8/9), 自动切换 MySQL 8.4"
        ver="84"
    fi
    local nv; case "$ver" in 51) nv="5.1";; 57) nv="5.7";; 80) nv="8.0";; 84) nv="8.4";; *) nv="$ver";; esac
    local arch; arch=$(uname -m)
    [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ] || arch="x86_64"
    local base="" style=""
    for dom in "https://repo.mysql.com" "https://mirrors.tuna.tsinghua.edu.cn/mysql" "https://mirrors.cloud.tencent.com/mysql" "https://mirrors.aliyun.com/mysql" "https://repo.huaweicloud.com/mysql"; do
        if curl -sI --connect-timeout 5 --max-time 8 "${dom}/yum/mysql-${nv}-community/el/${rel}/${arch}/repodata/repomd.xml" >/dev/null 2>&1; then
            base="$dom"; style="nested"; break
        fi
        if curl -sI --connect-timeout 5 --max-time 8 "${dom}/yum/mysql-${nv}-community-el${rel}-${arch}/repodata/repomd.xml" >/dev/null 2>&1; then
            base="$dom"; style="flat"; break
        fi
    done
    [ -z "$base" ] && { warn "MySQL ${nv} yum 源均不可达, 请检查网络或改用离线包"; return 1; }
    log "MySQL ${nv} yum 源: $base (${style}, el${rel}/${arch})"
    local mainurl
    if [ "$style" = "flat" ]; then
        mainurl="${base}/yum/mysql-${nv}-community-el${rel}/\$basearch/"
    else
        mainurl="${base}/yum/mysql-${nv}-community/el/${rel}/\$basearch/"
    fi
    cat > /etc/yum.repos.d/mysql-community.repo <<REPO
# MySQL Community Server ${nv} (由 TLBB 万能环境安装器生成)
[mysql${ver}-community]
name=MySQL ${nv} Community Server
baseurl=${mainurl}
enabled=1
gpgcheck=0
REPO
    # 8.0/8.4 依赖 mysql-tools / mysql-connectors 公共源 (部分 libs 包)
    if [ "$ver" = "80" ] || [ "$ver" = "84" ]; then
        for extra in mysql-tools-community mysql-connectors-community; do
            local extraurl=""
            if [ "$style" = "flat" ]; then
                curl -sI --connect-timeout 5 --max-time 8 "${base}/yum/${extra}-el${rel}-${arch}/repodata/repomd.xml" >/dev/null 2>&1 && extraurl="${base}/yum/${extra}-el${rel}/\$basearch/"
            else
                curl -sI --connect-timeout 5 --max-time 8 "${base}/yum/${extra}/el/${rel}/${arch}/repodata/repomd.xml" >/dev/null 2>&1 && extraurl="${base}/yum/${extra}/el/${rel}/\$basearch/"
            fi
            [ -n "$extraurl" ] || continue
            cat >> /etc/yum.repos.d/mysql-community.repo <<REPO

[${extra}]
name=MySQL ${extra}
baseurl=${extraurl}
enabled=1
gpgcheck=0
REPO
        done
    fi
    local m; m=$(rhel_pkgmgr)
    $m clean all >/dev/null 2>&1
    $m makecache >/dev/null 2>&1 || { warn "MySQL 源 makecache 失败, 尝试继续安装"; }
    return 0
}

# ---------- MySQL 官方 rpm 直下兜底 ----------
# 某些网络环境(代理/防火墙按 TLS 指纹分流) dnf/yum 访问 repo.mysql.com 会 404,
# 而 curl 直连正常. 此函数用 curl 解析 repomd/primary 拿最新包名, 下载 rpm 后本地安装.
rhel_download_mysql_rpm() {
    # $1: 57|80   $2: rel (6|7|8|9|10)
    local ver="$1" rel="$2" arch
    arch=$(uname -m); [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ] || arch="x86_64"
    # 已装则直接跳过 (重跑安装器时不重复下载)
    rpm -q mysql-community-server >/dev/null 2>&1 && { log "MySQL ${ver} 已安装, 跳过 rpm 直下"; return 0; }
    # 目录结构: 官方/镜像均可能为嵌套 (mysql-8.0-community/el/N/arch) 或扁平
    # (mysql-8.0-community-elN-arch, 清华/腾讯/阿里镜像), 老路径 mysql80-community
    # 部分环境仍有效. 逐域名×逐路径探测 repodata, 选第一个可达的 base.
    local nv; case "$ver" in 51) nv="5.1";; 57) nv="5.7";; 80) nv="8.0";; 84) nv="8.4";; *) nv="$ver";; esac
    local base="" dom b
    for dom in "https://repo.mysql.com" "https://mirrors.tuna.tsinghua.edu.cn/mysql" "https://mirrors.cloud.tencent.com/mysql" "https://mirrors.aliyun.com/mysql" "https://repo.huaweicloud.com/mysql"; do
        for b in \
            "${dom}/yum/mysql-${nv}-community/el/${rel}/${arch}" \
            "${dom}/yum/mysql-${nv}-community-el${rel}-${arch}" \
            "${dom}/yum/mysql${ver}-community/el/${rel}/${arch}" \
            "${dom}/yum/mysql${ver}-community-el${rel}-${arch}"; do
            if curl -s --connect-timeout 8 --max-time 20 -o /dev/null -w "%{http_code}" "$b/repodata/repomd.xml" | grep -q "^200"; then
                base="$b"; break 2
            fi
        done
    done
    [ -z "$base" ] && { warn "所有 MySQL 源路径均不可达 (repodata 探测失败)"; return 1; }
    log "MySQL 源路径命中: $base"
    local tmpd="/tmp/tlbb-mysql-rpm"; rm -rf "$tmpd"; mkdir -p "$tmpd"
    log "源安装失败, 兜底: curl 直下 MySQL ${ver} rpm 本地安装 (绕过 dnf 指纹分流)"
    # 1. repomd -> primary
    curl -s --connect-timeout 8 --max-time 30 -o "$tmpd/repomd.xml" "$base/repodata/repomd.xml" || { warn "repomd 下载失败"; return 1; }
    local primary
    primary=$(grep -oE 'href="repodata/[^"]*primary[^"]*"' "$tmpd/repomd.xml" | sed 's/href="//;s/"//' | head -1)
    [ -z "$primary" ] && { warn "repomd 解析失败"; return 1; }
    curl -s --connect-timeout 8 --max-time 300 -o "$tmpd/primary.xml.gz" "$base/$primary" || { warn "primary 下载失败"; return 1; }
    # 2. 提取 6 个核心包的最新版文件名 (排除 debug/devel/test), 每包只取版本号最大的一个
    # 注意: 分组 key 必须取前 4 字段, 否则 mysql-community-client 与
    #       mysql-community-client-plugins 会合并为同组 (前者被吞, mysql 命令缺失)
    # 关键: 只保留最新版一套, 混装多版本会导致 mysqld initialize segfault
    #       (如 8.0.30 的 el9 包在 Stream 9 glibc 2.34 上有已知崩溃)
    local files
    files=$(zcat "$tmpd/primary.xml.gz" 2>/dev/null | grep -oE '<location href="[^"]*\.rpm"' | sed 's/<location href="//;s/".*//' | \
        grep -E "mysql-community-(server|client|client-plugins|libs|common|icu-data-files)-[0-9]" | grep -vE "debug|devel|test|backup|router|shell|connector" | \
        sed 's#.*/##' | sort -V | awk -F- '{k=$1"-"$2"-"$3"-"$4; if($0>a[k]) a[k]=$0} END{for(k in a) print a[k]}')
    [ -z "$files" ] && { warn "primary 中未解析到 rpm 文件名"; return 1; }
    local total_mb=0 cnt=0
    # 3. 静默下载最新版 (curl -s 不输出, 仅结束时汇总一行)
    local f ok=1
    for f in $files; do
        if ! curl -s --connect-timeout 8 --max-time 300 -o "$tmpd/$f" "$base/$f"; then
            warn "下载失败: $f"; ok=0; break
        fi
        local sz; sz=$(du -k "$tmpd/$f" 2>/dev/null | cut -f1); total_mb=$((total_mb + sz)); cnt=$((cnt + 1))
    done
    [ "$ok" = "0" ] && return 1
    # 4. 本地安装: 先按依赖顺序 rpm -Uvh (可覆盖已装旧版), dnf localinstall 兜底
    #    顺序: common -> libs -> client-plugins -> client -> icu-data-files -> server
    local ord f2
    for ord in common libs client-plugins client icu-data-files server; do
        f2=$(echo "$files" | grep "mysql-community-${ord}-" | head -1)
        [ -n "$f2" ] && rpm -Uvh "$tmpd/$f2" --nodeps --force >/dev/null 2>&1
    done
    rpm -q mysql-community-server >/dev/null 2>&1 || \
        dnf --disablerepo="mysql*" localinstall -y "$tmpd"/*.rpm >/dev/null 2>&1 || \
        { warn "rpm 本地安装失败"; return 1; }
    # 5. 补装 mysqld 系统依赖 (rpm --nodeps 场景可能缺失 libaio/protobuf, 否则 mysqld 起不来)
    local dep
    for dep in libaio protobuf-lite numactl-libs; do
        rpm -q "$dep" >/dev/null 2>&1 || rhel_pkg_install "$dep" >/dev/null 2>&1
    done
    log "MySQL ${ver} rpm 直下完成: ${cnt} 个最新版 rpm (server/client/libs/common, 共 $((total_mb/1024)) MB)"
    return 0
}

# ---------- 在线源+直下均失败时, 自动降级本地离线包 ----------
# offline/rpm-packages/<branch>/mysql<ver>/*.rpm 已备齐的环境 (断网/代理/TLS指纹分流场景)
rhel_fallback_offline_rpm() {
    local mver; mver=$(select_mysql_version)
    local rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH/mysql${mver}"
    # 兼容旧结构: <branch>/ 根下放 rpm
    [ -d "$rdir" ] || rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
    if [ ! -d "$rdir" ] || ! ls "$rdir"/*.rpm >/dev/null 2>&1; then
        warn "本地离线包目录不存在或为空: $rdir"
        return 1
    fi
    warn "在线源与直下均失败, 自动降级本地离线包: $rdir"
    local installed=0 skipped=0 r pkgname
    for r in "$rdir"/*.rpm; do
        pkgname=$(rpm -qp --qf '%{NAME}' "$r" 2>/dev/null)
        [ -z "$pkgname" ] && continue
        if rpm -q "$pkgname" >/dev/null 2>&1; then
            skipped=$((skipped + 1)); continue
        fi
        rpm -ivh "$r" --nodeps --force >/dev/null 2>&1 && installed=$((installed + 1))
    done
    log "离线降级安装: 新装 ${installed} 个, 已存在跳过 ${skipped} 个"
    # 验证 mysql-server 是否装上
    if rpm -q mysql-server >/dev/null 2>&1 || rpm -q mysql-community-server >/dev/null 2>&1; then
        log "MySQL 本地离线包降级安装成功"
        return 0
    fi
    warn "mysql-server 未装上 (依赖缺失), 尝试整目录强制安装..."
    rpm -ivh "$rdir"/*.rpm --nodeps --force >/dev/null 2>&1 || return 1
    rpm -q mysql-server >/dev/null 2>&1 || rpm -q mysql-community-server >/dev/null 2>&1
}

# ---------- 安装数据库 ----------
rhel_install_db() {
    local mver; mver=$(select_mysql_version)
    log "数据库方案: MySQL ${mver} (可 TLBB_MYSQL_VERSION=51|57|80|84 覆盖)"
    # 离线模式: 优先本地 rpm 包目录 (rpm-packages/<branch>/mysql<ver>/)
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
        local vdir="${rdir}/mysql${mver}"
        # 兼容旧结构: 老版本打包直接把 rpm 放在 <branch>/ 下
        [ -d "$vdir" ] && rdir="$vdir"
        if [ -d "$rdir" ] && find "$rdir" -maxdepth 1 \( -name '*mysql*.rpm' -o -name 'MySQL*.rpm' -o -name '*mysql*.tar.gz' \) 2>/dev/null | grep -q .; then
            log "离线安装 MySQL ${mver} (rpm: $rdir)..."
            # 优先 tar 包 (el7 MySQL 5.1.73 bundled 格式)
            local mtar; mtar=$(find "$rdir" -maxdepth 1 -name "MySQL*.tar.gz" 2>/dev/null | head -1)
            if [ -n "$mtar" ]; then
                local tmpd=/tmp/tlbb-mysql; rm -rf $tmpd; mkdir -p $tmpd
                tar zxf "$mtar" -C $tmpd
                yum -y remove mysql-libs 2>/dev/null || true
                rpm -ivh $tmpd/mysql-client.rpm --nodeps --force >/dev/null 2>&1 || true
                rpm -ivh $tmpd/mysql-server.rpm --nodeps --force >/dev/null 2>&1 || \
                    { warn "mysql-server 离线安装失败, 尝试目录内全部 rpm"; rpm -ivh "$rdir"/*.rpm --nodeps --force >/dev/null 2>&1 || die "离线数据库安装失败"; }
                return 0
            fi
            # rpm 目录安装: 跳过已安装包(避免降级系统核心库), 未安装的按依赖顺序安装
            local installed=0 skipped=0
            for r in "$rdir"/*.rpm; do
                local pkgname; pkgname=$(rpm -qp --qf '%{NAME}' "$r" 2>/dev/null)
                [ -z "$pkgname" ] && continue
                if rpm -q "$pkgname" >/dev/null 2>&1; then
                    skipped=$((skipped + 1)); continue
                fi
                rpm -ivh "$r" --nodeps --force >/dev/null 2>&1 && installed=$((installed + 1))
            done
            log "离线 MySQL ${mver} rpm 安装完成: 新装 ${installed} 个, 已存在跳过 ${skipped} 个"
            # 若 mysql-server 未装上(如依赖缺失), 再尝试完整依赖安装
            if ! rpm -q mysql-server >/dev/null 2>&1; then
                warn "mysql-server 未装上, 尝试完整依赖安装..."
                rpm -ivh "$rdir"/*.rpm --nodeps --force >/dev/null 2>&1 || \
                    { warn "数据库 rpm 安装失败, 尝试依赖补齐"; rpm -ivh "$rdir"/*.rpm >/dev/null 2>&1 || die "离线数据库安装失败"; }
            fi
            return 0
        fi
        warn "离线模式未找到 MySQL ${mver} rpm (offline/rpm-packages/$SYS_BRANCH/mysql${mver}/), 数据库需联网安装"
        warn "提示: 联网机器上 'bash scripts/pack_offline.sh --full <branch>' 补齐后放入该目录"
        # 离线包缺失时尝试 curl 直下官方源兜底 (部分服务器仅 repo.mysql.com 可达)
        warn "尝试 curl 直下 MySQL ${mver} 官方源兜底..."
        if rhel_download_mysql_rpm "$mver" "${SYS_BRANCH#el}" 2>/dev/null; then
            log "MySQL ${mver} 官方源直下兜底安装完成"
            return 0
        fi
        die "离线数据库包缺失且官方直下失败, 安装中止 (或将 offline/rpm-packages/$SYS_BRANCH/mysql${mver}/ 补齐后重试)"
    fi
    case "$mver" in
        51)
            case "$SYS_BRANCH" in
                el5)
                    log "安装 MySQL 5.1 (yum 源, vault 归档)..."
                    rhel_pkg_install mysql-server || die "MySQL 安装失败"
                    ;;
                el6)
                    log "安装 MySQL 5.1 (yum 源)..."
                    rhel_pkg_install mysql-server || die "MySQL 安装失败"
                    ;;
                el7)
                    log "安装 MySQL 5.1.73 (离线 bundled rpm)..."
                    rhel_pkg_install perl
                    local mytar
                    mytar=$(off_get el7 MySQL.tar.gz)
                    [ -z "$mytar" ] && mytar=$(find / -name "MySQL.tar.gz" 2>/dev/null | head -1)
                    if [ -z "$mytar" ]; then
                        warn "未找到离线 MySQL 5.1 包, 尝试 yum 安装 mysql (vault 归档)"
                        rhel_pkg_install mysql-server || die "MySQL 安装失败"
                    else
                        local tmpd=/tmp/tlbb-mysql; rm -rf $tmpd; mkdir -p $tmpd
                        tar zxf "$mytar" -C $tmpd
                        yum -y remove mysql-libs 2>/dev/null || true
                        rpm -ivh $tmpd/mysql-client.rpm --nodeps --force >/dev/null 2>&1 || \
                            warn "mysql-client 安装失败(继续)"
                        rpm -ivh $tmpd/mysql-server.rpm --nodeps --force >/dev/null 2>&1 || \
                            die "mysql-server 离线安装失败"
                    fi
                    ;;
                *)
                    warn "MySQL 5.1 不适配 ${SYS_BRANCH}, 改按 5.7 安装"
                    rhel_config_mysql_repo 57
                    rhel_pkg_install mysql-community-server || die "MySQL 5.7 安装失败"
                    ;;
            esac
            ;;
        57)
            log "安装 MySQL 5.7 (官方源)..."
            local rel7; rel7="${SYS_BRANCH#el}"
            # MySQL 5.7 无 el8+ 官方包, config 内部会自动切 8.0
            if ! rhel_config_mysql_repo 57 || ! rhel_pkg_install mysql-community-server; then
                rhel_download_mysql_rpm 57 "$rel7" || \
                rhel_fallback_offline_rpm || die "MySQL 5.7 安装失败(源/直下/离线包均失败)"
            fi
            ;;
        80)
            log "安装 MySQL 8.0 (官方源)..."
            local rel8; rel8="${SYS_BRANCH#el}"
            # el10: 官方 8.0 无 el10 包, 自动改用 MySQL 8.4 (LTS) 安装
            if [ "$rel8" = "10" ]; then
                warn "MySQL 8.0 无官方 el10 包 (官方 8.0 仅提供 el6/7/8/9), 自动改用 MySQL 8.4"
                if ! rhel_config_mysql_repo 84 || ! rhel_pkg_install mysql-community-server; then
                    rhel_download_mysql_rpm 84 "$rel8" || \
                    rhel_fallback_offline_rpm || die "MySQL 8.4 安装失败(源/直下/离线包均失败, 请检查网络或 offline/ 目录)"
                fi
            # el9 (CentOS Stream 9 / RHEL9+ / Rocky/Alma 9): 系统 AppStream 自带 MySQL 8.0 包,
            # 官方源 el9 目录结构已变更易 404, 优先走系统源 (实测 CentOS Stream 9 mysql-server=8.0.46)
            # 离线模式网络可用时也强制配置国内源走系统源 (避免直下兜底引入旧版/混装)
            elif [ "$rel8" -ge 9 ] 2>/dev/null; then
                [ "${TLBB_OFFLINE_MODE:-0}" = "1" ] && rhel_config_repo force >/dev/null 2>&1
                if rhel_pkg_install mysql-server; then
                    log "MySQL 8.0 通过系统源 (AppStream mysql-server) 安装完成"
                elif ! rhel_config_mysql_repo 80 || ! rhel_pkg_install mysql-community-server; then
                    rhel_download_mysql_rpm 80 "$rel8" || \
                    rhel_fallback_offline_rpm || die "MySQL 8.0 安装失败(源/直下/离线包均失败, 请检查网络或 offline/ 目录)"
                fi
            ;;
        84)
            log "安装 MySQL 8.4 (官方/国内镜像源)..."
            local rel84; rel84="${SYS_BRANCH#el}"
            # el10 (CentOS Stream 10): 官方 8.0 无 el10 包, 8.4 为官方 LTS;
            # 清华/腾讯/阿里镜像 el10 的 8.4 仓库实测可用, 优先 repo 安装
            if ! rhel_config_mysql_repo 84 || ! rhel_pkg_install mysql-community-server; then
                rhel_download_mysql_rpm 84 "$rel84" || \
                rhel_fallback_offline_rpm || die "MySQL 8.4 安装失败(源/直下/离线包均失败, 请检查网络或 offline/ 目录)"
            fi
            ;;
        *) die "不支持的 MySQL 版本: $mver (可选 51|57|80|84)";;
    esac
    # 装完数据库后禁用 MySQL 官方源: 指纹分流/失效环境会让该源持续 404,
    # 拖累后续所有 dnf 操作 (unixODBC/其他组件安装失败)
    if [ "$mver" != "51" ]; then
        dnf config-manager --set-disabled "mysql*" >/dev/null 2>&1 || \
            sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/mysql*.repo >/dev/null 2>&1
        log "MySQL 官方源已禁用 (避免失效源拖累后续安装)"
    fi
}

rhel_start_db() {
    log "启动数据库 (MySQL $(select_mysql_version))..."
    local mver; mver=$(select_mysql_version)
    case "$SYS_BRANCH" in
        el5|el6|el7)
            if [ "$mver" = "80" ] || [ "$mver" = "84" ] || [ "$mver" = "57" ]; then
                systemctl enable mysqld 2>/dev/null || true
                systemctl start mysqld 2>/dev/null || service mysqld start 2>/dev/null || \
                    { warn "mysqld 启动失败, 尝试直接运行"; mysqld_safe --user=mysql >/dev/null 2>&1 & sleep 6; }
            else
                service mysqld start 2>/dev/null || service mysql start 2>/dev/null || \
                { /etc/init.d/mysqld start 2>/dev/null || { warn "mysqld 启动失败, 尝试直接运行"; mysqld_safe --user=mysql >/dev/null 2>&1 & sleep 6; }; }
            fi
            chkconfig mysqld on 2>/dev/null || true
            ;;
        el8|el9|el10)
            # 确保 mysqld 系统依赖就位 (rpm --nodeps 直下场景可能缺失, 否则 mysqld 起不来)
            local dep
            for dep in libaio protobuf-lite numactl-libs; do
                rpm -q "$dep" >/dev/null 2>&1 || rhel_pkg_install "$dep" >/dev/null 2>&1
            done
            # MySQL 官方 rpm 服务名为 mysqld (非 mariadb)
            systemctl enable mysqld 2>/dev/null || true
            systemctl start mysqld 2>/dev/null || service mysqld start 2>/dev/null || true
            ;;
    esac
    sleep 4
    # 等待就绪 (5.7/8.0 首启需先完成初始化)
    local i
    for i in $(seq 1 20); do
        # mysqladmin ping 加 </dev/null, 避免交互式 Enter password: 提示
        mysqladmin ping </dev/null >/dev/null 2>&1 && { log "数据库已就绪"; return 0; }
        sleep 2
    done
    # 启动失败: 自动清理旧版本(混装/坏包)并重装最新版, 一次性自愈 (防递归)
    if [ "${TLBB_MYSQL_REPAIRED:-0}" != "1" ]; then
        warn "数据库未完全就绪, 自动修复: 清理旧 MySQL 包与残留 datadir 后重装最新版..."
        TLBB_MYSQL_REPAIRED=1
        rhel_repair_mysql
        return 0
    fi
    warn "数据库仍未就绪, 输出 mysqld 日志便于定位:"
    journalctl -u mysqld --no-pager -n 10 2>/dev/null | tail -5 >&2 || true
}

# ---------- MySQL 启动失败自愈 ----------
# 场景: 旧版残留(如 8.0.30 el9 包在 Stream 9 上 initialize segfault) / 混版本安装 /
#       datadir 半初始化残留. 卸载全部 mysql 包 -> 备份清理 datadir -> 重新安装最新版并启动
rhel_repair_mysql() {
    local m; m=$(rhel_pkgmgr)
    systemctl stop mysqld >/dev/null 2>&1 || systemctl stop mysql >/dev/null 2>&1 || true
    pkill -9 mysqld 2>/dev/null || true
    sleep 1
    # 卸载全部 mysql 相关包 (官方版 + 系统自带版)
    $m remove -y mysql-community-* mysql-server mysql mysql-libs mysql-common mysql-errmsg 2>/dev/null || true
    rpm -qa 2>/dev/null | grep -E '^(mysql|mysql-community)' | xargs -r rpm -e --nodeps 2>/dev/null || true
    # 备份并清理残留 datadir / 配置文件 (避免半初始化数据干扰新版本首启)
    local bak="/var/lib/mysql.broken.$(date +%s)"
    [ -d /var/lib/mysql ] && mv /var/lib/mysql "$bak" 2>/dev/null || true
    rm -rf /var/lib/mysql-files /var/lib/mysql-keyring /var/lib/mysql-community* 2>/dev/null || true
    rm -f /etc/my.cnf /etc/my.cnf.d/*.cnf 2>/dev/null || true
    # 清除 rpm 缓存中的旧包
    $m clean all >/dev/null 2>&1 || true
    log "已清理旧 MySQL (datadir 备份: ${bak}), 重新安装最新版..."
    rhel_install_mysql
    rhel_start_db
}

# ---------- MySQL 5.7/8.0 首启临时密码处理 ----------
# MySQL 5.7+ 首次启动生成临时 root 密码 (写入日志)
# 日志路径随发行版不同: el7/el8 = /var/log/mysqld.log, el9 = /var/log/mysql/mysqld.log
# 脚本自动提取并重置为 TLBB_DB_PASS, 同时卸载 validate_password 强度校验
rhel_handle_first_boot() {
    local mver; mver=$(select_mysql_version)
    [ "$mver" = "51" ] && return 0
    local tmp_pw="" logf=""
    # 多路径探测日志 (覆盖 el7/el8/el9 不同发行版日志位置)
    for logf in /var/log/mysqld.log /var/log/mysql/mysqld.log /var/log/mysql/error.log; do
        [ -f "$logf" ] || continue
        tmp_pw=$(grep -a "temporary password" "$logf" 2>/dev/null | tail -1 | sed 's/.*: //')
        [ -n "$tmp_pw" ] && break
    done
    # journald 兜底 (日志未落盘时从 systemd journal 提取)
    if [ -z "$tmp_pw" ] && command -v journalctl >/dev/null 2>&1; then
        tmp_pw=$(journalctl -u mysqld --no-pager 2>/dev/null | grep -a "temporary password" | tail -1 | sed 's/.*: //')
    fi

    if [ -z "$tmp_pw" ]; then
        # 无临时密码(已初始化过): 先尝试空密码登录
        # 所有 mysql 命令加 </dev/null, 避免交互式 Enter password: 提示 (输出到 /dev/tty)
        if mysql -uroot -p'' -e "SELECT 1;" </dev/null >/dev/null 2>&1; then
            log "MySQL 空密码可登录, 正在设置 root 密码为 ${TLBB_DB_PASS} ..."
            mysql -uroot -p'' -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" </dev/null 2>/dev/null || \
                warn "空密码设置失败, 将由后续账号配置兜底"
            return 0
        fi
        # 终极兜底: skip-grant-tables 重置 root 密码 (覆盖日志缺失/密码未知场景)
        log "未找到临时密码, 使用 skip-grant-tables 重置 root 密码为 ${TLBB_DB_PASS} ..."
        systemctl stop mysqld >/dev/null 2>&1 || systemctl stop mysql >/dev/null 2>&1
        pkill -9 mysqld 2>/dev/null; sleep 2
        local skiptype="conf"
        if command -v mysqld_safe >/dev/null 2>&1; then
            # 老版本 (el6/el7/部分el8): 有 mysqld_safe
            skiptype="safe"
            mysqld_safe --skip-grant-tables --skip-networking >/dev/null 2>&1 &
        else
            # el9+ MySQL 8.0: 弃用 mysqld_safe, 用配置文件方式
            echo -e "[mysqld]\nskip-grant-tables\nskip-networking" > /etc/my.cnf.d/zz-skip-grant.cnf
            systemctl start mysqld >/dev/null 2>&1 || systemctl start mysql >/dev/null 2>&1
        fi
        local i=0
        until mysql -uroot -e "SELECT 1;" </dev/null >/dev/null 2>&1 || [ $i -ge 20 ]; do sleep 1; i=$((i + 1)); done
        if mysql -uroot -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" </dev/null >/dev/null 2>&1; then
            log "skip-grant-tables 重置成功 (方式: $skiptype)"
        else
            warn "skip-grant-tables 重置失败 (老版本可用 SET PASSWORD 方式)"
            mysql -uroot -e "FLUSH PRIVILEGES; SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${TLBB_DB_PASS}'); FLUSH PRIVILEGES;" </dev/null >/dev/null 2>&1
        fi
        # 恢复正常启动 (去掉 skip-grant 配置)
        if [ "$skiptype" = "safe" ]; then
            mysqladmin -uroot -p"${TLBB_DB_PASS}" shutdown </dev/null >/dev/null 2>&1 || pkill -9 mysqld_safe 2>/dev/null
        else
            systemctl stop mysqld >/dev/null 2>&1 || systemctl stop mysql >/dev/null 2>&1
            rm -f /etc/my.cnf.d/zz-skip-grant.cnf
        fi
        sleep 3
        systemctl start mysqld >/dev/null 2>&1 || systemctl restart mysqld >/dev/null 2>&1 || \
            systemctl start mysql >/dev/null 2>&1
        # 等待就绪
        i=0
        until mysqladmin -uroot -p"${TLBB_DB_PASS}" ping </dev/null >/dev/null 2>&1 || [ $i -ge 20 ]; do sleep 1; i=$((i + 1)); done
        log "MySQL 已用 ${TLBB_DB_PASS} 重启就绪"
        return 0
    fi
    log "检测到 MySQL 首次临时密码, 正在重置为 ${TLBB_DB_PASS} ..."
    # 8.0/5.7: 临时密码默认过期, 且受 validate_password 策略约束 (123456 不满足 MEDIUM)
    # 两段式: ①先用满足策略的强密码重置(首条语句必须 ALTER USER) ②登录强密码→卸载组件→改回弱密码
    local strong="Gstest@${TLBB_DB_PASS}"
    mysql -uroot -p"$tmp_pw" --connect-expired-password </dev/null \
        -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$strong';" 2>/dev/null && \
    mysql -uroot -p"$strong" </dev/null \
        -e "UNINSTALL COMPONENT 'file://component_validate_password' 2>/dev/null; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
    mysql -uroot -p"$tmp_pw" --connect-expired-password </dev/null \
        -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
    mysql -uroot -p"$tmp_pw" </dev/null \
        -e "SET PASSWORD = PASSWORD('${TLBB_DB_PASS}'); FLUSH PRIVILEGES;" 2>/dev/null || \
        { warn "临时密码重置失败, 请手动检查 MySQL 日志"; }
}

# ---------- 建库导入 ----------
# 初始数据包按 MySQL 档位组织: offline/sql/mysql{51,57,80}/
#   mysql51/  web.sql + tlbbdb.sql            (utf8, 行格式 COMPACT, MySQL 5.1 原生)
#   mysql57/  web.sql + tlbbdb.sql            (utf8mb4, 行格式 DYNAMIC, MySQL 5.7)
#   mysql80/  web.sql + tlbbdb.sql + tlbbdb_10.sql (utf8mb4, DYNAMIC; 对应 odbc.ini
#             tlbbdb_main/tlbbdb/CHAR_DBTABASE DSN 的物理库 tlbbdb, tlbbdb_10 DSN 的 tlbbdb_10)
# MySQL 8.4 与 8.0 的 utf8mb4/DYNAMIC SQL 与认证行为一致, 直接复用 mysql80/ 目录
# 每份 sql 自带 CREATE DATABASE IF NOT EXISTS + USE 头, 直接导入即可
rhel_setup_db() {
    local mver; mver=$(select_mysql_version)
    # 8.4 复用 8.0 的 SQL 包 (utf8mb4/DYNAMIC 一致)
    local sqldir_ver="mysql${mver}"; [ "$mver" = "84" ] && sqldir_ver="mysql80"
    local sql_dir="$TLBB_OFFLINE_DIR/sql/${sqldir_ver}"
    if [ ! -d "$sql_dir" ]; then
        sql_dir=$(dirname "$(off_get "sql/${sqldir_ver}" tlbbdb.sql 2>/dev/null)" 2>/dev/null || true)
        [ -d "$sql_dir" ] || sql_dir="$TLBB_OFFLINE_DIR/sql/${sqldir_ver}"
    fi
    local tlbbdb="$sql_dir/tlbbdb.sql" web="$sql_dir/web.sql" t10="$sql_dir/tlbbdb_10.sql"
    [ -f "$tlbbdb" ] || tlbbdb=$(find "$TLBB_OFFLINE_DIR/sql" -name "tlbbdb.sql" 2>/dev/null | head -1)
    [ -f "$web" ] || web=$(find "$TLBB_OFFLINE_DIR/sql" -name "web.sql" 2>/dev/null | head -1)

    rhel_handle_first_boot

    # 数据库结构: 3库(新端 tlbbdb_10+tlbbdb_main+web) / 2库(怀旧 tlbbdb+web); 8.0/8.4 交互选择, 其余固定 2 库
    local dblayout="${TLBB_DB_LAYOUT:-3}"
    local main_db="tlbbdb" need_t10=0
    if { [ "$mver" = "80" ] || [ "$mver" = "84" ]; } && [ "$dblayout" = "3" ]; then
        main_db="tlbbdb_main"; need_t10=1
    fi

    log "配置 MySQL ${mver} 账号并建库 (${dblayout} 库结构, 主库 ${main_db})..."
    case "$mver" in
        80|84)
            # MySQL 8.0/8.4: 卸载密码强度组件 + 强制 native 认证 (兼容 ODBC 3.51/老驱动)
            # 注意: UNINSTALL COMPONENT 对未安装组件会报错并中止 mysql -e, 必须单独执行且忽略失败
            mysql -uroot -p"${TLBB_DB_PASS}" -e "UNINSTALL COMPONENT 'file://component_validate_password';" 2>/dev/null
            mysql -uroot -e "UNINSTALL COMPONENT 'file://component_validate_password';" 2>/dev/null
            mysql -uroot -p"${TLBB_DB_PASS}" -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;" 2>/dev/null || \
            { warn "MySQL ${mver} 账号配置失败, 尝试本地无密登录"; mysql -uroot -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;" 2>/dev/null; }
            # 按 2/3 库结构建库
            if [ "$need_t10" = "1" ]; then
                mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb_main CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS tlbbdb_10 CHARACTER SET utf8mb4;" 2>/dev/null
            else
                mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8mb4;" 2>/dev/null
            fi
            ;;
        57)
            # MySQL 5.7: ALTER USER native 认证
            mysql -uroot -p"${TLBB_DB_PASS}" -e "
SET GLOBAL validate_password_policy=LOW 2>/dev/null;
SET GLOBAL validate_password_length=6 2>/dev/null;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8mb4;
FLUSH PRIVILEGES;" 2>/dev/null || \
            { warn "MySQL 5.7 账号配置失败, 尝试本地无密登录"; mysql -uroot -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8mb4;
FLUSH PRIVILEGES;" 2>/dev/null; }
            ;;
        *)
            # 老 MySQL (5.1/5.5/5.6) 走 Password 列
            mysql -uroot -e "use mysql; update user set Password=PASSWORD('${TLBB_DB_PASS}') where User='root'; FLUSH PRIVILEGES;" 2>/dev/null
            mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${TLBB_DB_PASS}' WITH GRANT OPTION;" 2>/dev/null
            mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' IDENTIFIED BY '${TLBB_MYSQL_PASSWORD}' WITH GRANT OPTION;" 2>/dev/null
            mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb; CREATE DATABASE IF NOT EXISTS web;" 2>/dev/null
            ;;
    esac
    # 确保 root 密码生效 (MySQL 8.0 空密码时创建后再次确认)
    if [ "$mver" = "80" ] || [ "$mver" = "84" ] || [ "$mver" = "57" ]; then
        local cs="utf8mb4"
        if [ "$need_t10" = "1" ]; then
            mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb_main CHARACTER SET ${cs}; CREATE DATABASE IF NOT EXISTS web CHARACTER SET ${cs}; CREATE DATABASE IF NOT EXISTS tlbbdb_10 CHARACTER SET ${cs};" 2>/dev/null
        else
            mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET ${cs}; CREATE DATABASE IF NOT EXISTS web CHARACTER SET ${cs};" 2>/dev/null
        fi
    fi
    # 导入初始数据 (包内自带 CREATE DATABASE/USE, 直接导入; 字符集按档位)
    # 兼容说明: 无论 SQL 文件是否自带 CREATE DATABASE/USE 头, 目标库均已先建好,
    # 且导入时显式指定目标库 (mysql <db> < file) -> 无头 SQL 也能正确落入目标库
    local cs_opt="utf8"; [ "$mver" = "57" ] || [ "$mver" = "80" ] || [ "$mver" = "84" ] && cs_opt="utf8mb4"
    if [ -f "$tlbbdb" ] && [ -f "$web" ]; then
        log "导入初始数据 (MySQL ${mver}: $sql_dir, 字符集 ${cs_opt}, ${dblayout} 库结构)..."
        if [ "$main_db" = "tlbbdb" ]; then
            mysql -uroot -p"${TLBB_DB_PASS}" --default-character-set="$cs_opt" "$main_db" < "$tlbbdb" 2>/dev/null && log "tlbbdb 导入成功" || warn "tlbbdb 导入失败 (请检查 ${sql_dir}/tlbbdb.sql)"
        else
            # 3 库模式: 主库物理名为 tlbbdb_main, 改写 tlbbdb.sql 的 CREATE DATABASE/USE 头后导入
            sed 's/CREATE DATABASE IF NOT EXISTS tlbbdb\b/CREATE DATABASE IF NOT EXISTS tlbbdb_main/g; s/^USE tlbbdb;/USE tlbbdb_main;/g' "$tlbbdb" | mysql -uroot -p"${TLBB_DB_PASS}" --default-character-set="$cs_opt" "$main_db" 2>/dev/null && log "tlbbdb_main 导入成功" || warn "tlbbdb_main 导入失败 (请检查 ${sql_dir}/tlbbdb.sql)"
        fi
        mysql -uroot -p"${TLBB_DB_PASS}" --default-character-set="$cs_opt" web < "$web" 2>/dev/null && log "web 导入成功" || warn "web 导入失败"
        if [ "$need_t10" = "1" ] && [ -f "$t10" ]; then
            mysql -uroot -p"${TLBB_DB_PASS}" --default-character-set="$cs_opt" tlbbdb_10 < "$t10" 2>/dev/null && log "tlbbdb_10 导入成功" || warn "tlbbdb_10 导入失败"
        fi
    else
        warn "未找到离线 SQL 文件, 跳过自动导入"
        if [ "$need_t10" = "1" ]; then
            warn "在线模式下请手动导入: 将 tlbbdb.sql / web.sql / tlbbdb_10.sql 上传到服务器后执行:"
            warn "  sed 's/CREATE DATABASE IF NOT EXISTS tlbbdb;/CREATE DATABASE IF NOT EXISTS tlbbdb_main;/; s/^USE tlbbdb;/USE tlbbdb_main;/' tlbbdb.sql | mysql -uroot -p${TLBB_DB_PASS}"
            warn "  mysql -uroot -p${TLBB_DB_PASS} < web.sql"
            warn "  mysql -uroot -p${TLBB_DB_PASS} < tlbbdb_10.sql"
        else
            warn "在线模式下请手动导入: 将 tlbbdb.sql / web.sql 上传到服务器后执行:"
            warn "  mysql -uroot -p${TLBB_DB_PASS} < tlbbdb.sql"
            warn "  mysql -uroot -p${TLBB_DB_PASS} < web.sql"
        fi
        warn "SQL 文件位置参考: offline/sql/${sqldir_ver}/ 目录"
    fi
}

# ---------- 安装 ODBC ----------
rhel_install_odbc() {
    case "$SYS_BRANCH" in
        el5)
            log "安装离线 unixODBC 2.2.11 + MySQL ODBC 3.51 (el5)..."
            local r
            for r in unixODBC-2.2.11-el5.rpm unixODBC-libs-5.8.rpm unixODBC-devel-5.8.rpm libtool-ltdl-5.8.rpm libtool-ltdl-devel-5.8.rpm; do
                local rr; rr=$(off_get el5 "$r")
                [ -n "$rr" ] && rpm -ivh "$rr" --nodeps --force >/dev/null 2>&1
            done
            local mco5 myd5
            mco5=$(off_get el5 mysql-connector-odbc-5.1.rpm)
            [ -n "$mco5" ] && rpm -ivh "$mco5" --nodeps --force >/dev/null 2>&1
            # 兜底: 从 myodbc 包直接解 32 位驱动
            myd5=$(off_get el6 myodbc.tar.gz)
            [ -n "$myd5" ] && tar zxf "$myd5" -C /usr/lib 2>/dev/null
            ;;
        el6)
            log "安装离线 unixODBC + MySQL ODBC 3.51..."
            local uo mco myd
            uo=$(off_get el6 unixODBC.rpm); mco=$(off_get el6 mysql-connector-odbc.rpm); myd=$(off_get el6 myodbc.tar.gz)
            [ -n "$uo" ] && rpm -ivh "$uo" --nodeps --force >/dev/null 2>&1
            [ -n "$mco" ] && rpm -ivh "$mco" --nodeps --force >/dev/null 2>&1
            [ -n "$myd" ] && tar zxf "$myd" -C /usr/lib 2>/dev/null
            ;;
        el7)
            log "安装离线 unixODBC 2.2.11 + MySQL ODBC 3.51..."
            local libt odt
            libt=$(off_get el7 lib.tar.gz); odt=$(off_get el7 ODBC.tar.gz)
            local tmpd=/tmp/tlbb-odbc; rm -rf $tmpd; mkdir -p $tmpd
            [ -n "$libt" ] && tar zxf "$libt" -C $tmpd
            if [ -d "$tmpd" ]; then
                for r in $tmpd/unixODBC-libs.rpm $tmpd/unixODBC-2.2.11.rpm $tmpd/libtool-ltdl.rpm $tmpd/unixODBC-devel.rpm; do
                    [ -f "$r" ] && rpm -ivh "$r" --nodeps --force >/dev/null 2>&1
                done
            fi
            [ -n "$odt" ] && tar zxf "$odt" -C $tmpd 2>/dev/null
            [ -f "$tmpd/mysql-odbc.rpm" ] && rpm -ivh "$tmpd/mysql-odbc.rpm" --nodeps --force >/dev/null 2>&1
            [ -f "$tmpd/odbc.tar.gz" ] && tar zxf "$tmpd/odbc.tar.gz" -C /usr/lib 2>/dev/null
            # 64 位 MySQL ODBC 5.1 驱动 (libmyodbc5) - 供 64 位 unixODBC/管理工具
            local drv64 d64
            drv64=$(off_get el7/libmyodbc5-64bit libmyodbc5w.so)
            if [ -n "$drv64" ]; then
                local ddir; ddir=$(dirname "$drv64")
                mkdir -p /usr/lib64
                cp -f "$ddir/libmyodbc5w.so" /usr/lib64/libmyodbc.so 2>/dev/null
                cp -f "$ddir/libmyodbc5S.so" /usr/lib64/libmyodbcS.so 2>/dev/null
                cp -f "$ddir/libmyodbc5a.so" /usr/lib64/libmyodbc5a.so 2>/dev/null
                log "64 位 MySQL ODBC 驱动已就位 (/usr/lib64/libmyodbc.so)"
            else
                warn "未找到 64 位 ODBC 驱动(可选), 仅 32 位驱动可用"
            fi
            ;;
        el8|el9|el10)
            log "安装 unixODBC (源/离线包) + 离线 32 位 MySQL ODBC 3.51 驱动..."
            # 离线模式: 从 rpm-packages 本地安装 unixODBC (odbc/ 子目录或根目录)
            if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
                local rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
                local odfile; odfile=$(find "$rdir" -maxdepth 2 -name "unixODBC*.rpm" 2>/dev/null | head -1)
                if [ -n "$odfile" ]; then
                    for r in "$(dirname "$odfile")"/unixODBC*.rpm; do rpm -ivh "$r" --nodeps --force >/dev/null 2>&1; done
                    log "离线 unixODBC 安装完成 (来自 $(dirname "$odfile"))"
                else
                    # 离线缺失时网络可用则自动在线装 unixODBC
                    rhel_offline_fallback_online unixODBC "unixODBC" >/dev/null 2>&1 || \
                        warn "离线模式未找到 unixODBC rpm 且无网络, isql 可能不可用"
                fi
            else
                local m; m=$(rhel_pkgmgr)
                # 先检测是否已安装, 避免重复安装时的误报警告
                if command -v isql >/dev/null 2>&1; then
                    log "unixODBC 64位已存在 (isql 可用), 跳过安装"
                else
                    $m -y install unixODBC unixODBC-devel 2>/dev/null || warn "unixODBC(64位) 安装失败"
                fi
                # 32 位 unixODBC (可选, el9 老端用 64 位驱动为主)
                if ls /usr/lib/libodbc.so.* >/dev/null 2>&1; then
                    log "unixODBC 32位库已存在, 跳过安装"
                else
                    $m -y install unixODBC.i686 2>/dev/null || warn "unixODBC(32位) 安装失败 (可选, el9+ 端通常不需要)"
                fi
            fi
            # 32 位驱动复制到 /usr/lib (el8/el9/el10 主要用 64 位驱动, 32 位为可选兼容)
            local drv; drv=$(off_get el8_el9_el10/libmyodbc3-32bit libmyodbc3-3.51.27.so)
            [ -z "$drv" ] && drv=$(find / -name "libmyodbc3-3.51.27.so" 2>/dev/null | head -1)
            if [ -n "$drv" ]; then
                cp -f "$drv" /usr/lib/libmyodbc3.so 2>/dev/null
                # SONAME 兼容: 老驱动需要 libodbcinst.so.1 / libodbc.so.1
                if [ -f /usr/lib/libodbcinst.so.2 ]; then ln -sf /usr/lib/libodbcinst.so.2 /usr/lib/libodbcinst.so.1; fi
                if [ -f /usr/lib/libodbc.so.2 ]; then ln -sf /usr/lib/libodbc.so.2 /usr/lib/libodbc.so.1; fi
                ln -sf /usr/lib/libmyodbc3.so /usr/lib/libmyodbc3-3.51.27.so 2>/dev/null
            elif ls /usr/lib64/libmaodbc.so >/dev/null 2>&1 || ls /usr/lib64/libmyodbc.so >/dev/null 2>&1; then
                # el9+ 使用 64 位驱动 (libmaodbc.so = mariadb-connector-odbc, 或 libmyodbc.so)
                log "64 位 MySQL ODBC 驱动已就位 (/usr/lib64), 32 位驱动非必需 (el9+ 端为 64 位进程)"
            else
                warn "未找到 MySQL ODBC 驱动 (32 位 libmyodbc3 或 64 位 libmaodbc/libmyodbc)"
                warn "离线模式请确保 rpm-packages/$SYS_BRANCH 内含 mariadb-connector-odbc (libmaodbc.so) 或在线安装 mysql-connector-odbc"
            fi
            ;;
    esac
}

# ---------- 配置 ODBC ----------
rhel_config_odbc() {
    log "配置 /etc/odbc.ini ..."
    mkdir -p /etc
    # 驱动自动检测: 64 位 libmaodbc (MySQL8 ODBC) → 64 位 libmyodbc → 32 位 libmyodbc3
    local drvpath=""
    for c in /usr/lib64/libmaodbc.so /usr/lib64/libmyodbc.so /usr/lib/libmyodbc3.so; do
        [ -f "$c" ] && { drvpath="$c"; break; }
    done
    [ -z "$drvpath" ] && drvpath="/usr/lib/libmyodbc3.so"
    # 按 2/3 库结构决定主库名与是否含 tlbbdb_10 (与建库一致)
    local mver; mver=$(select_mysql_version)
    local dblayout="${TLBB_DB_LAYOUT:-3}"
    local main_db="tlbbdb" has_t10=0
    if { [ "$mver" = "80" ] || [ "$mver" = "84" ]; } && [ "$dblayout" = "3" ]; then
        main_db="tlbbdb_main"; has_t10=1
    fi
    # 端类型检测: 武道四 v3 端 (Server 目录存在 luoluo 子目录) → 游戏库映射到 tlbbdb_10 (仅 3 库结构)
    local game_db="$main_db"
    if [ "$has_t10" = "1" ] && ls -d /home/tlbb/tlbb*/Server/luoluo >/dev/null 2>&1; then
        game_db="tlbbdb_10"
        log "检测到武道四 v3 端 (luoluo 目录), 启用四段 DSN 映射"
    fi
    cat > /etc/odbc.ini <<INI
[tlbbdb_main]
Driver          = $drvpath
Description     = TLBB Main DB (角色库)
SERVER          = 127.0.0.1
PORT            = 3306
USER            = root
Password        = ${TLBB_DB_PASS}
Database        = ${main_db}
OPTION          = 3
SOCKET          =

[tlbbdb]
Driver          = $drvpath
Description     = TLBB Game DB
SERVER          = 127.0.0.1
PORT            = 3306
USER            = root
Password        = ${TLBB_DB_PASS}
Database        = ${game_db}
OPTION          = 3
SOCKET          =

INI
    if [ "$has_t10" = "1" ]; then
        cat >> /etc/odbc.ini <<INI
[tlbbdb_10]
Driver          = $drvpath
Description     = TLBB Game DB (动态库)
SERVER          = 127.0.0.1
PORT            = 3306
USER            = root
Password        = ${TLBB_DB_PASS}
Database        = tlbbdb_10
OPTION          = 3
SOCKET          =

INI
    fi
    cat >> /etc/odbc.ini <<INI
[CHAR_DBTABASE]
Driver          = $drvpath
Description     = TLBB Char DB
SERVER          = 127.0.0.1
PORT            = 3306
USER            = root
Password        = ${TLBB_DB_PASS}
Database        = ${main_db}
OPTION          = 3
SOCKET          =
INI
    cat > /etc/odbcinst.ini <<INI
[ODBC Drivers]
MySQL ODBC 3.51 Driver=Installed
MySQL ODBC 5.1 Driver 64=Installed

[MySQL ODBC 3.51 Driver]
Driver=$drvpath
Setup=/usr/lib/libmyodbc3S.so
UsageCount=1

[MySQL ODBC 5.1 Driver 64]
Driver=/usr/lib64/libmyodbc.so
Setup=/usr/lib64/libmyodbcS.so
UsageCount=1
INI
    chmod 644 /etc/my.cnf 2>/dev/null
    log "ODBC 配置完成"
}

# ---------- 验证 ----------
rhel_verify() {
    log "验证安装结果..."
    local ok=0
    mysqladmin ping >/dev/null 2>&1 && { info "  [OK] 数据库运行中"; ok=$((ok+1)); } || warn "  [!!] 数据库未运行"
    if ls /usr/lib/libmyodbc3.so >/dev/null 2>&1 || ls /usr/lib64/libmaodbc.so >/dev/null 2>&1 || ls /usr/lib64/libmyodbc.so >/dev/null 2>&1; then
        info "  [OK] MySQL ODBC 驱动就位 (32位 libmyodbc3 / 64位 libmaodbc|libmyodbc)"
        ok=$((ok+1))
    fi
    command -v isql >/dev/null 2>&1 && { info "  [OK] unixODBC isql 可用"; ok=$((ok+1)); }
    # 按 2/3 库结构验证主库与 tlbbdb_10 (与建库一致)
    local mver; mver=$(select_mysql_version)
    local main_db="tlbbdb"
    { [ "$mver" = "80" ] || [ "$mver" = "84" ]; } && [ "${TLBB_DB_LAYOUT:-3}" = "3" ] && main_db="tlbbdb_main"
    local t
    t=$(mysql -uroot -p"${TLBB_DB_PASS}" -N -e "use ${main_db}; show tables;" 2>/dev/null | wc -l)
    [ "$t" -gt 0 ] && { info "  [OK] ${main_db} 含 ${t} 张表"; ok=$((ok+1)); } || warn "  [!!] ${main_db} 无表(需手动导入)"
    if [ "$mver" = "80" ] || [ "$mver" = "84" ]; then
        if [ "${TLBB_DB_LAYOUT:-3}" = "3" ]; then
            local t10
            t10=$(mysql -uroot -p"${TLBB_DB_PASS}" -N -e "use tlbbdb_10; show tables;" 2>/dev/null | wc -l)
            [ "$t10" -gt 0 ] && { info "  [OK] tlbbdb_10 含 ${t10} 张表"; ok=$((ok+1)); } || warn "  [!!] tlbbdb_10 无表(需手动导入)"
        fi
    fi
    # 可选组件验证 (仅当对应命令存在; 不纳入 4 项基础分, 纯状态展示)
    command -v nginx >/dev/null 2>&1 && { nginx -v >/dev/null 2>&1 && info "  [OK] 可选组件 nginx: $(nginx -v 2>&1 | head -1)" || warn "  [!!] 可选组件 nginx 验证失败"; }
    command -v php >/dev/null 2>&1 && { php -v >/dev/null 2>&1 && info "  [OK] 可选组件 PHP: $(php -v 2>/dev/null | head -1)" || warn "  [!!] 可选组件 PHP 验证失败"; }
    command -v redis-server >/dev/null 2>&1 || command -v valkey-server >/dev/null 2>&1 && { \
        local rcli2="redis-cli"; command -v valkey-cli >/dev/null 2>&1 && rcli2="valkey-cli"
        $rcli2 ping >/dev/null 2>&1 && info "  [OK] 可选组件 Redis/Valkey 运行中 (127.0.0.1:6379)" || warn "  [!!] 可选组件 Redis/Valkey 未运行"; }
    info "验证: ${ok}/4 通过"
    [ "$ok" -ge 3 ] && return 0 || return 1
}

# ---------- 离线 rpm 查找 (根目录或子目录, 兼容 download_offline/pack_offline 两种放置) ----------
# $1: 包名前缀 (如 redis/nginx/php/unixODBC), 返回第一个匹配文件绝对路径 (空=未找到)
rhel_off_find() {
    local prefix="$1" base="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
    find "$base" -maxdepth 2 -name "${prefix}*.rpm" 2>/dev/null | head -1
}

# ---------- 离线组件缺失时的在线回退 ----------
# 有网场景: 离线包缺组件不再直接跳过, 自动强制配置国内源并用 dnf 在线安装;
# 无网场景: 明确提示可加 --online 重试. $1=包名, $2=展示名
rhel_offline_fallback_online() {
    local pkg="$1" name="$2"
    if curl -sI --connect-timeout 3 --max-time 5 https://mirrors.aliyun.com >/dev/null 2>&1; then
        log "离线包未含 ${name} rpm, 检测到网络可用, 自动回退在线源安装..."
        rhel_config_repo force >/dev/null 2>&1
        if rhel_pkg_install "$pkg" >/dev/null 2>&1; then
            log "${name} 在线源安装完成"
            return 0
        fi
        warn "${name} 在线源安装失败 (源不可用或网络异常)"
        return 1
    fi
    warn "离线包未含 ${name} rpm 且无网络, 跳过 (可选组件, 联网后执行 bash install.sh --online 可补装)"
    return 1
}

# ---------- 可选组件: redis (billing/GM 工具依赖, 密码默认 gsgameshare.com) ----------
# el10 官方 AppStream/EPEL 已无 redis 服务器包 (RHEL 10 生态以 Valkey 8 替代, RESP 协议兼容),
# 在线/离线均自动回退 valkey (命令 valkey-server/valkey-cli, 端口与 requirepass 配置一致)
rhel_install_redis() {
    local rp="${TLBB_REDIS_PASSWORD:-gsgameshare.com}"
    if rpm -q redis >/dev/null 2>&1 || command -v redis-server >/dev/null 2>&1 || \
       rpm -q valkey >/dev/null 2>&1 || command -v valkey-server >/dev/null 2>&1; then
        log "Redis/Valkey 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        log "离线模式: 检查本地 redis/valkey rpm (offline/rpm-packages/$SYS_BRANCH/)..."
        local rfile; rfile=$(rhel_off_find redis); [ -z "$rfile" ] && rfile=$(rhel_off_find valkey)
        if [ -n "$rfile" ]; then
            rpm -ivh "$(dirname "$rfile")"/{redis,valkey}*.rpm --nodeps --force >/dev/null 2>&1 && \
                log "离线 redis/valkey rpm 安装完成" || warn "离线 redis/valkey rpm 安装失败"
        else
            rhel_offline_fallback_online redis "redis" || rhel_offline_fallback_online valkey "valkey" || true
        fi
    else
        if [ "$SYS_BRANCH" = "el10" ]; then
            # el10: AppStream 无 redis 包, 官方以 valkey 替代
            rhel_pkg_install valkey 2>/dev/null || { warn "valkey 安装失败 (el10 替代 redis, 可选组件, billing 验证需要)"; return 0; }
            log "el10 官方已无 redis 包, 已安装 Valkey (Redis 兼容替代, 端口/密码协议一致)"
        else
            rhel_pkg_install redis 2>/dev/null || { warn "redis 安装失败 (可选组件, billing 验证需要)"; return 0; }
        fi
    fi
    command -v redis-server >/dev/null 2>&1 || command -v valkey-server >/dev/null 2>&1 || return 0
    local rcli="redis-cli"; command -v valkey-cli >/dev/null 2>&1 && rcli="valkey-cli"
    # 启动 (兼容 systemd 服务名 redis/redis-server/valkey 与裸进程)
    systemctl enable --now redis >/dev/null 2>&1 || \
    systemctl enable --now redis-server >/dev/null 2>&1 || \
    systemctl enable --now valkey >/dev/null 2>&1 || \
    systemctl enable --now valkey-server >/dev/null 2>&1 || \
        { [ -x /usr/sbin/valkey-server ] && valkey-server --daemonize yes >/dev/null 2>&1 || \
          redis-server --daemonize yes >/dev/null 2>&1 || warn "redis/valkey 启动失败"; }
    sleep 2
    # 设置密码 (对齐 .env REDIS_PASSWORD, 默认 gsgameshare.com; 配置文件路径兼容 redis/valkey)
    local rconf=""
    [ -f /etc/redis.conf ] && rconf=/etc/redis.conf
    [ -f /etc/redis/redis.conf ] && rconf=/etc/redis/redis.conf
    [ -f /etc/valkey/valkey.conf ] && rconf=/etc/valkey/valkey.conf
    if [ -n "$rconf" ]; then
        grep -q "^requirepass" "$rconf" && \
            sed -i "s/^requirepass.*/requirepass ${rp}/" "$rconf" || \
            echo "requirepass ${rp}" >> "$rconf"
    fi
    if $rcli -a "$rp" ping >/dev/null 2>&1; then
        log "Redis/Valkey 安装成功并验证通过: 127.0.0.1:6379, 密码已配置 ${rp}"
    else
        systemctl restart valkey >/dev/null 2>&1 || systemctl restart redis >/dev/null 2>&1 || true
        sleep 2
        $rcli -a "$rp" ping >/dev/null 2>&1 && \
            log "Redis/Valkey 密码已设置为 ${rp} 并验证通过" || \
            warn "Redis/Valkey 密码设置失败, 请手动: $rcli CONFIG SET requirepass ${rp}"
    fi
}

# ---------- 可选组件: nginx (系统源最新版) ----------
rhel_install_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        log "Nginx 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local nfile; nfile=$(rhel_off_find nginx)
        if [ -n "$nfile" ]; then
            rpm -ivh "$(dirname "$nfile")"/nginx*.rpm --nodeps --force >/dev/null 2>&1 && \
                log "离线 nginx rpm 安装完成" || warn "离线 nginx rpm 安装失败"
        else
            rhel_offline_fallback_online nginx "nginx" || true
        fi
    else
        rhel_pkg_install nginx 2>/dev/null || { warn "nginx 安装失败 (当前系统源无可用包或网络异常, 已跳过)"; return 0; }
    fi
    command -v nginx >/dev/null 2>&1 || return 0
    # 安装成功验证
    if nginx -v >/dev/null 2>&1; then
        log "Nginx 安装成功并验证通过: $(nginx -v 2>&1 | head -1)"
    else
        warn "Nginx 已安装但验证失败 (nginx -v 异常, 请检查二进制完整性)"
    fi
    systemctl enable --now nginx >/dev/null 2>&1 || service nginx start >/dev/null 2>&1 || true
}

# ---------- 可选组件: php (系统源最新版) ----------
rhel_install_php() {
    if command -v php >/dev/null 2>&1; then
        log "PHP 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local pfile; pfile=$(rhel_off_find php)
        if [ -n "$pfile" ]; then
            rpm -ivh "$(dirname "$pfile")"/php*.rpm --nodeps --force >/dev/null 2>&1 && \
                log "离线 php rpm 安装完成" || warn "离线 php rpm 安装失败"
        else
            rhel_offline_fallback_online php "php" || true
        fi
    else
        # AppStream/base 源即当前发行版可装的最新版 (el8+ 为 php 8.x, el7 为 5.4)
        rhel_pkg_install php 2>/dev/null || { warn "php 安装失败 (当前系统源无可用包或网络异常, 已跳过)"; return 0; }
        rhel_pkg_install php-fpm >/dev/null 2>&1 || true   # php-fpm 可选 (老系统源无此包时忽略)
    fi
    command -v php >/dev/null 2>&1 || return 0
    # 安装成功验证
    if php -v >/dev/null 2>&1; then
        log "PHP 安装成功并验证通过: $(php -v 2>/dev/null | head -1)"
    else
        warn "PHP 已安装但验证失败 (php -v 异常, 请检查依赖是否完整)"
    fi
    # 启动 php-fpm (el8+ 为 php-fpm, el6 为 php-fpm; 老系统无 systemctl 时用 service)
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files php-fpm >/dev/null 2>&1; then
        systemctl enable --now php-fpm >/dev/null 2>&1 || true
    else
        service php-fpm start >/dev/null 2>&1 || true
    fi
}

# ---------- 可选组件交互安装 (nginx/php/redis, 安装完 MySQL 后询问, 默认 no) ----------
rhel_install_optional() {
    log "可选组件询问 (nginx/php/redis, 直接回车=不安装)..."
    [ "$(ask_optional_component nginx "Web 服务器, 用于 GM 工具/网站 (将安装当前系统源最新版)" TLBB_OPT_NGINX)" = "1" ] && rhel_install_nginx
    [ "$(ask_optional_component php "PHP 运行时, 配合 Nginx 提供网站服务 (将安装当前系统源最新版)" TLBB_OPT_PHP)" = "1" ] && rhel_install_php
    [ "$(ask_optional_component redis "Redis 内存数据库, billing/GM 工具依赖, 密码默认 gsgameshare.com (将安装当前系统源最新版)" TLBB_OPT_REDIS)" = "1" ] && rhel_install_redis
}

# ---------- RHEL 主流程 ----------
rhel_install() {
    local m; m=$(rhel_pkgmgr)
    log "使用包管理器: $m"
    ask_dbpass
    rhel_config_repo
    rhel_install_compat
    rhel_install_db
    rhel_start_db
    rhel_setup_db
    rhel_install_optional   # nginx/php/redis 可选组件 (交互询问, 默认不安装)
    rhel_install_odbc
    rhel_config_odbc
    rhel_verify
}
