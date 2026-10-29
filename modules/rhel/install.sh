#!/bin/bash
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
    $m -y install "$@" >/dev/null 2>&1 || { warn "包安装失败: $*"; return 1; }
}

# ---------- 配置国内 yum/dnf 源 ----------
rhel_config_repo() {
    # 离线模式: 跳过源配置, 直接使用本地安装包
    [ "${TLBB_OFFLINE_MODE:-0}" = "1" ] && { log "离线模式: 跳过 yum/dnf 源配置, 使用本地 rpm 安装包"; return 0; }
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
    $m clean all >/dev/null 2>&1
    $m makecache >/dev/null 2>&1 || warn "makecache 失败, 请检查网络"
}

# ---------- 安装 32 位兼容库 ----------
rhel_install_compat() {
    log "安装 32 位兼容库 (glibc/libstdc++/libnsl/libcrypt)..."
    # 离线模式: 尝试本地 rpm 包目录 (offline/rpm-packages/<elX>/), 否则仅提示
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
        if [ -d "$rdir" ] && ls "$rdir"/*.rpm >/dev/null 2>&1; then
            local installed=0 skipped=0
            for r in "$rdir"/*.rpm; do
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
            warn "离线模式未找到兼容库 rpm (offline/rpm-packages/$SYS_BRANCH/), 32 位库可能缺失"
            warn "提示: 联网机器上 'yumdownloader --resolve glibc.i686' 等获取后放入该目录"
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
            $m -y install glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 gcc glibc-devel.i686 2>/dev/null || \
            $m -y install glibc.i686 libstdc++.i686 2>/dev/null || warn "32 位库安装不完整, 请检查源"
            ;;
    esac
    log "32 位兼容库安装完成"
}

# ---------- 配置 MySQL 官方 yum 源 ----------
# 注意: MySQL 5.7 官方只提供 el6/el7 包(无 el8); MySQL 8.0 提供 el8/el9
# 国内镜像(阿里云/华为云/腾讯云)只有 MySQL 发行包镜像, 无 yum 仓库结构,
# 因此按"逐镜像探测具体 repomd.xml"决定 base, 全部不可达时用官方 repo.mysql.com
rhel_config_mysql_repo() {
    # $1: 57|80
    local ver="$1" rel="${SYS_BRANCH#el}"
    [ -z "$rel" ] && rel="7"
    # 防御: MySQL 5.7 无 el8 包, 自动改 8.0
    if [ "$ver" = "57" ] && { [ "$rel" = "8" ] || [ "$rel" = "9" ] || [ "$rel" = "10" ]; }; then
        warn "MySQL 5.7 无官方 el${rel} 包, 自动切换 MySQL 8.0"
        ver="80"
    fi
    local arch; arch=$(uname -m)
    [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ] || arch="x86_64"
    local base=""
    for dom in "https://repo.mysql.com" "https://mirrors.aliyun.com/mysql" "https://repo.huaweicloud.com/mysql" "https://mirrors.cloud.tencent.com/mysql"; do
        if curl -sI --connect-timeout 5 --max-time 8 "${dom}/yum/mysql-${ver}-community/el/${rel}/${arch}/repodata/repomd.xml" >/dev/null 2>&1; then
            base="$dom"; break
        fi
    done
    [ -z "$base" ] && { warn "MySQL ${ver} 官方 yum 源均不可达, 请检查网络或改用离线包"; return 1; }
    log "MySQL ${ver} yum 源: $base (el${rel}/${arch})"
    cat > /etc/yum.repos.d/mysql-community.repo <<REPO
# MySQL Community Server ${ver} (由 TLBB 万能环境安装器生成)
[mysql${ver}-community]
name=MySQL ${ver} Community Server
baseurl=${base}/yum/mysql-${ver}-community/el/${rel}/\$basearch/
enabled=1
gpgcheck=0
REPO
    # 8.0 依赖 mysql-tools / mysql-connectors 公共源 (部分 libs 包)
    if [ "$ver" = "80" ]; then
        for extra in mysql-tools-community mysql-connectors-community; do
            if curl -sI --connect-timeout 5 --max-time 8 "${base}/yum/${extra}/el/${rel}/${arch}/repodata/repomd.xml" >/dev/null 2>&1; then
                cat >> /etc/yum.repos.d/mysql-community.repo <<REPO

[${extra}]
name=MySQL ${extra}
baseurl=${base}/yum/${extra}/el/${rel}/\$basearch/
enabled=1
gpgcheck=0
REPO
            fi
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
    # MySQL 官方源目录结构已变更: 新路径 mysql-8.0-community/el/N/arch (2024+),
    # 老路径 mysql80-community/el/N/arch / mysql80-community-elN-arch 部分环境仍有效.
    # 逐路径探测 repodata, 选第一个可达的 base (el9 实测: mysql-8.0-community/el/9/x86_64 200).
    local nv; case "$ver" in 57) nv="5.7";; 80) nv="8.0";; *) nv="$ver";; esac
    local base=""
    for b in \
        "https://repo.mysql.com/yum/mysql-${nv}-community/el/${rel}/${arch}" \
        "https://repo.mysql.com/yum/mysql${ver}-community/el/${rel}/${arch}" \
        "https://repo.mysql.com/yum/mysql${ver}-community-el${rel}-${arch}"; do
        if curl -s --connect-timeout 8 --max-time 20 -o /dev/null -w "%{http_code}" "$b/repodata/repomd.xml" | grep -q "^200"; then
            base="$b"; break
        fi
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
    # 2. 提取 6 个核心包的最新版文件名 (排除 debug/devel/test)
    local files
    files=$(zcat "$tmpd/primary.xml.gz" 2>/dev/null | grep -oE '<location href="[^"]*\.rpm"' | sed 's/<location href="//;s/".*//' | \
        grep -E "mysql-community-(server|client|client-plugins|libs|common|icu-data-files)-[0-9]" | grep -vE "debug|devel|test|backup|router|shell|connector" | \
        sed 's#.*/##' | sort -V | awk -F- '{k=$1"-"$2"-"$3} a[k]=$0 END{for(k in a) print a[k]}')
    [ -z "$files" ] && { warn "primary 中未解析到 rpm 文件名"; return 1; }
    # 3. 逐个下载
    local f ok=1
    for f in $files; do
        log "  下载 $f ..."
        curl -s --connect-timeout 8 --max-time 300 -o "$tmpd/$f" "$base/$f" || { warn "下载失败: $f"; ok=0; break; }
    done
    [ "$ok" = "0" ] && return 1
    # 4. 本地安装 (禁用 mysql repo 避免触发失效源)
    dnf --disablerepo="mysql*" localinstall -y "$tmpd"/*.rpm >/dev/null 2>&1 || \
    rpm -ivh "$tmpd"/*.rpm --nodeps --force >/dev/null 2>&1 || { warn "rpm 本地安装失败"; return 1; }
    log "MySQL ${ver} rpm 直下安装完成 (最新版)"
    return 0
}

# ---------- 安装数据库 ----------
rhel_install_db() {
    local mver; mver=$(select_mysql_version)
    log "数据库方案: MySQL ${mver} (可 TLBB_MYSQL_VERSION=51|57|80 覆盖)"
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
        die "离线数据库包缺失, 安装中止 (或将 offline/rpm-packages/$SYS_BRANCH/mysql${mver}/ 补齐后重试)"
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
                rhel_download_mysql_rpm 57 "$rel7" || die "MySQL 5.7 安装失败(源与直下均失败)"
            fi
            ;;
        80)
            log "安装 MySQL 8.0 (官方源)..."
            local rel8; rel8="${SYS_BRANCH#el}"
            # el9+ (CentOS Stream 9 / RHEL9+ / Rocky/Alma 9): 系统 AppStream 自带 MySQL 8.0 包,
            # 官方源 el9 目录结构已变更易 404, 优先走系统源 (实测 CentOS Stream 9 mysql-server=8.0.46)
            if [ "$rel8" -ge 9 ] 2>/dev/null && rhel_pkg_install mysql-server; then
                log "MySQL 8.0 通过系统源 (AppStream mysql-server) 安装完成"
            elif ! rhel_config_mysql_repo 80 || ! rhel_pkg_install mysql-community-server; then
                rhel_download_mysql_rpm 80 "$rel8" || die "MySQL 8.0 安装失败(源与直下均失败)"
            fi
            ;;
        *) die "不支持的 MySQL 版本: $mver (可选 51|57|80)";;
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
            if [ "$mver" = "80" ] || [ "$mver" = "57" ]; then
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
            # MySQL 官方 rpm 服务名为 mysqld (非 mariadb)
            systemctl enable mysqld 2>/dev/null || true
            systemctl start mysqld 2>/dev/null || service mysqld start 2>/dev/null || true
            ;;
    esac
    sleep 4
    # 等待就绪 (5.7/8.0 首启需先完成初始化)
    local i
    for i in $(seq 1 20); do
        mysqladmin ping >/dev/null 2>&1 && { log "数据库已就绪"; return 0; }
        sleep 2
    done
    warn "数据库未完全就绪, 继续尝试..."
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
        # 无临时密码(已初始化过): 先尝试无密/空密登录
        if mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then
            log "MySQL 本地无密可登录, 正在设置 root 密码为 ${TLBB_DB_PASS} ..."
            mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
                warn "无密设置密码失败, 将由后续账号配置兜底"
            return 0
        fi
        # 空密码登录
        if mysql -uroot -p'' -e "SELECT 1;" >/dev/null 2>&1; then
            log "MySQL 空密码可登录, 正在设置 root 密码为 ${TLBB_DB_PASS} ..."
            mysql -uroot -p'' -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
                warn "空密码设置密码失败, 将由后续账号配置兜底"
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
        until mysql -uroot -e "SELECT 1;" >/dev/null 2>&1 || [ $i -ge 20 ]; do sleep 1; i=$((i + 1)); done
        if mysql -uroot -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
            log "skip-grant-tables 重置成功 (方式: $skiptype)"
        else
            warn "skip-grant-tables 重置失败 (老版本可用 SET PASSWORD 方式)"
            mysql -uroot -e "FLUSH PRIVILEGES; SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${TLBB_DB_PASS}'); FLUSH PRIVILEGES;" >/dev/null 2>&1
        fi
        # 恢复正常启动 (去掉 skip-grant 配置)
        if [ "$skiptype" = "safe" ]; then
            mysqladmin -uroot -p"${TLBB_DB_PASS}" shutdown >/dev/null 2>&1 || pkill -9 mysqld_safe 2>/dev/null
        else
            systemctl stop mysqld >/dev/null 2>&1 || systemctl stop mysql >/dev/null 2>&1
            rm -f /etc/my.cnf.d/zz-skip-grant.cnf
        fi
        sleep 3
        systemctl start mysqld >/dev/null 2>&1 || systemctl restart mysqld >/dev/null 2>&1 || \
            systemctl start mysql >/dev/null 2>&1
        # 等待就绪
        i=0
        until mysqladmin -uroot -p"${TLBB_DB_PASS}" ping >/dev/null 2>&1 || [ $i -ge 20 ]; do sleep 1; i=$((i + 1)); done
        log "MySQL 已用 ${TLBB_DB_PASS} 重启就绪"
        return 0
    fi
    log "检测到 MySQL 首次临时密码, 正在重置为 ${TLBB_DB_PASS} ..."
    # 8.0/5.7: 临时密码默认过期, 且受 validate_password 策略约束 (123456 不满足 MEDIUM)
    # 两段式: ①先用满足策略的强密码重置(首条语句必须 ALTER USER) ②登录强密码→卸载组件→改回弱密码
    local strong="Gstest@${TLBB_DB_PASS}"
    mysql -uroot -p"$tmp_pw" --connect-expired-password \
        -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$strong';" 2>/dev/null && \
    mysql -uroot -p"$strong" \
        -e "UNINSTALL COMPONENT 'file://component_validate_password' 2>/dev/null; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
    mysql -uroot -p"$tmp_pw" --connect-expired-password \
        -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
    mysql -uroot -p"$tmp_pw" \
        -e "SET PASSWORD = PASSWORD('${TLBB_DB_PASS}'); FLUSH PRIVILEGES;" 2>/dev/null || \
        { warn "临时密码重置失败, 请手动检查 MySQL 日志"; }
}

# ---------- 建库导入 ----------
rhel_setup_db() {
    local mver; mver=$(select_mysql_version)
    local sql_dir
    sql_dir=$(off_get sql tlbbdb.sql 2>/dev/null)
    sql_dir=$(dirname "$sql_dir" 2>/dev/null || echo "$TLBB_OFFLINE_DIR/sql")
    local tlbbdb="$sql_dir/tlbbdb.sql" web="$sql_dir/web.sql"
    [ -f "$tlbbdb" ] || tlbbdb=$(find / -name "tlbbdb.sql" 2>/dev/null | head -1)
    [ -f "$web" ] || web=$(find / -name "web.sql" 2>/dev/null | head -1)

    rhel_handle_first_boot

    log "配置 MySQL ${mver} 账号并建库..."
    case "$mver" in
        80)
            # MySQL 8.0: 卸载密码强度组件 + 强制 native 认证 (兼容 ODBC 3.51/老驱动)
            # 注意: UNINSTALL COMPONENT 对未安装组件会报错并中止 mysql -e, 必须单独执行且忽略失败
            mysql -uroot -p"${TLBB_DB_PASS}" -e "UNINSTALL COMPONENT 'file://component_validate_password';" 2>/dev/null
            mysql -uroot -e "UNINSTALL COMPONENT 'file://component_validate_password';" 2>/dev/null
            mysql -uroot -p"${TLBB_DB_PASS}" -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
FLUSH PRIVILEGES;" 2>/dev/null || \
            { warn "MySQL 8.0 账号配置失败, 尝试本地无密登录"; mysql -uroot -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
FLUSH PRIVILEGES;" 2>/dev/null; }
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
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
FLUSH PRIVILEGES;" 2>/dev/null || \
            { warn "MySQL 5.7 账号配置失败, 尝试本地无密登录"; mysql -uroot -e "
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
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
    if [ "$mver" = "80" ] || [ "$mver" = "57" ]; then
        mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8; CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;" 2>/dev/null
    fi
    if [ -f "$tlbbdb" ] && [ -f "$web" ]; then
        mysql -uroot -p"${TLBB_DB_PASS}" tlbbdb < "$tlbbdb" 2>/dev/null && log "tlbbdb 导入成功"
        mysql -uroot -p"${TLBB_DB_PASS}" web < "$web" 2>/dev/null && log "web 导入成功"
    else
        warn "未找到离线 SQL 文件, 跳过导入 (可使用 Navicat 手动导入 offline/sql/)"
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
            # 离线模式: 从 rpm-packages 本地安装 unixODBC
            if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
                local rdir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
                if [ -d "$rdir" ] && ls "$rdir"/unixODBC*.rpm >/dev/null 2>&1; then
                    for r in "$rdir"/unixODBC*.rpm; do rpm -ivh "$r" --nodeps --force >/dev/null 2>&1; done
                    log "离线 unixODBC 安装完成 (来自 $rdir)"
                else
                    warn "离线模式未找到 unixODBC rpm (offline/rpm-packages/$SYS_BRANCH/), isql 可能不可用"
                fi
            else
                local m; m=$(rhel_pkgmgr)
                $m -y install unixODBC unixODBC-devel 2>/dev/null || warn "unixODBC(64位) 安装失败"
                $m -y install unixODBC.i686 2>/dev/null || warn "unixODBC(32位) 安装失败"
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
    # 端类型检测: 武道四 v3 端 (Server 目录存在 luoluo 子目录) → 游戏库映射到 tlbbdb_10
    local game_db="tlbbdb"
    if ls -d /home/tlbb/tlbb*/Server/luoluo >/dev/null 2>&1; then
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
Database        = tlbbdb
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

[CHAR_DBTABASE]
Driver          = $drvpath
Description     = TLBB Char DB
SERVER          = 127.0.0.1
PORT            = 3306
USER            = root
Password        = ${TLBB_DB_PASS}
Database        = tlbbdb
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
    local t
    t=$(mysql -uroot -p"${TLBB_DB_PASS}" -N -e "use tlbbdb; show tables;" 2>/dev/null | wc -l)
    [ "$t" -gt 0 ] && { info "  [OK] tlbbdb 含 ${t} 张表"; ok=$((ok+1)); } || warn "  [!!] tlbbdb 无表(需手动导入)"
    info "验证: ${ok}/4 通过"
    [ "$ok" -ge 3 ] && return 0 || return 1
}

# ---------- 安装 Redis (billing/GM 工具依赖) ----------
rhel_install_redis() {
    if rpm -q redis >/dev/null 2>&1 || command -v redis-server >/dev/null 2>&1; then
        log "Redis 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        log "离线模式: 检查本地 redis rpm (offline/rpm-packages/$SYS_BRANCH/)..."
        if ls "$TLBB_OFFLINE_DIR"/rpm-packages/$SYS_BRANCH/redis*.rpm >/dev/null 2>&1; then
            rpm -ivh "$TLBB_OFFLINE_DIR"/rpm-packages/$SYS_BRANCH/redis*.rpm --nodeps --force >/dev/null 2>&1 && \
                log "离线 redis rpm 安装完成" || warn "离线 redis rpm 安装失败"
        else
            warn "离线包未含 redis rpm, 跳过 (billing 验证可能需要 redis)"
        fi
    else
        rhel_pkg_install redis 2>/dev/null || warn "redis 安装失败 (可选组件, billing 验证需要)"
    fi
    command -v redis-server >/dev/null 2>&1 || return 0
    # 启动 (兼容 systemd 服务名 redis/redis-server 与裸进程)
    systemctl enable --now redis >/dev/null 2>&1 || \
    systemctl enable --now redis-server >/dev/null 2>&1 || \
        { redis-server --daemonize yes >/dev/null 2>&1 || warn "redis 启动失败"; }
    sleep 2
    # 设置密码 (对齐 .env REDIS_PASSWORD, 默认 gsgameshare.com)
    local rp="${TLBB_REDIS_PASSWORD:-gsgameshare.com}"
    if redis-cli -a "$rp" ping >/dev/null 2>&1; then
        log "Redis 运行中, 密码已配置"
    else
        redis-cli CONFIG SET requirepass "$rp" >/dev/null 2>&1 && \
            redis-cli -a "$rp" ping >/dev/null 2>&1 && log "Redis 密码已设置为 ${rp}" || \
            warn "Redis 密码设置失败, 请手动: redis-cli CONFIG SET requirepass ${rp}"
    fi
    # 持久化密码配置 (写入 redis 配置文件)
    local rconf=$(redis-server --version 2>/dev/null >/dev/null; find /etc -name "redis.conf" 2>/dev/null | head -1)
    if [ -n "$rconf" ]; then
        grep -q "^requirepass" "$rconf" && \
            sed -i "s/^requirepass.*/requirepass ${rp}/" "$rconf" || \
            echo "requirepass ${rp}" >> "$rconf"
    fi
    log "Redis 配置完成: 127.0.0.1:6379, 密码 ${rp}"
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
    rhel_install_redis
    rhel_install_odbc
    rhel_config_odbc
    rhel_verify
}
