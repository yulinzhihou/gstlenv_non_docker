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

# ---------- 安装数据库 ----------
rhel_install_db() {
    case "$SYS_BRANCH" in
        el5)
            log "安装 MySQL (yum 源, vault 归档)..."
            rhel_pkg_install mysql-server || die "MySQL 安装失败"
            service mysqld start 2>/dev/null || service mysql start 2>/dev/null || true
            chkconfig mysqld on 2>/dev/null || true
            ;;
        el6)
            log "安装 MySQL (yum 源)..."
            rhel_pkg_install mysql-server || die "MySQL 安装失败"
            service mysqld restart 2>/dev/null || service mysql restart 2>/dev/null || true
            chkconfig mysqld on 2>/dev/null || true
            ;;
        el7)
            log "安装离线 MySQL 5.1.73 (bundled rpm)..."
            rhel_pkg_install perl          # MySQL rpm 依赖 perl
            local mytar
            mytar=$(off_get el7 MySQL.tar.gz)
            [ -z "$mytar" ] && mytar=$(find / -name "MySQL.tar.gz" 2>/dev/null | head -1)
            if [ -z "$mytar" ]; then
                warn "未找到离线 MySQL 包, 回退 yum 安装 mariadb"
                rhel_pkg_install mariadb-server || die "数据库安装失败"
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
        el8|el9|el10)
            log "安装 MariaDB (国内源 dnf)..."
            local m; m=$(rhel_pkgmgr)
            $m -y install mariadb-server >/dev/null 2>&1 || \
            $m -y install mariadb-server >/dev/null 2>&1 || die "MariaDB 安装失败"
            ;;
    esac
}

rhel_start_db() {
    log "启动数据库..."
    case "$SYS_BRANCH" in
        el5|el6|el7)
            service mysqld start 2>/dev/null || service mysql start 2>/dev/null || \
            { /etc/init.d/mysqld start 2>/dev/null || { warn "mysqld 启动失败, 尝试直接运行"; mysqld_safe --user=mysql >/dev/null 2>&1 & sleep 6; }; }
            ;;
        el8|el9|el10)
            systemctl enable --now mariadb 2>/dev/null || systemctl start mariadb 2>/dev/null || \
            service mariadb start 2>/dev/null || true
            ;;
    esac
    sleep 4
    # 等待就绪
    local i
    for i in $(seq 1 15); do
        mysqladmin ping >/dev/null 2>&1 && { log "数据库已就绪"; return 0; }
        sleep 2
    done
    warn "数据库未完全就绪, 继续尝试..."
}

# ---------- 建库导入 ----------
rhel_setup_db() {
    local sql_dir
    sql_dir=$(off_get sql tlbbdb.sql 2>/dev/null)
    sql_dir=$(dirname "$sql_dir" 2>/dev/null || echo "$TLBB_OFFLINE_DIR/sql")
    local tlbbdb="$sql_dir/tlbbdb.sql" web="$sql_dir/web.sql"
    [ -f "$tlbbdb" ] || tlbbdb=$(find / -name "tlbbdb.sql" 2>/dev/null | head -1)
    [ -f "$web" ] || web=$(find / -name "web.sql" 2>/dev/null | head -1)

    log "创建数据库并导入 schema..."
    case "$SYS_BRANCH" in
        el8|el9|el10)
            # MariaDB (10.4+) root 默认走 unix_socket, 需改用密码认证
            mysql -uroot <<SQL 2>/dev/null
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${TLBB_DB_PASS}');
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'tlbb'@'%' IDENTIFIED BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON tlbbdb.* TO 'tlbb'@'%';
GRANT ALL PRIVILEGES ON web.* TO 'tlbb'@'%';
FLUSH PRIVILEGES;
SQL
            mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb; CREATE DATABASE IF NOT EXISTS web;" 2>/dev/null
            ;;
        *)
            # 老 MySQL (5.1/5.x) 走 Password 列
            mysql -uroot -e "use mysql; update user set Password=PASSWORD('${TLBB_DB_PASS}') where User='root'; FLUSH PRIVILEGES;" 2>/dev/null
            mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${TLBB_DB_PASS}' WITH GRANT OPTION;" 2>/dev/null
            mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb; CREATE DATABASE IF NOT EXISTS web;" 2>/dev/null
            ;;
    esac
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
            log "安装 unixODBC (源) + 离线 32 位 MySQL ODBC 3.51 驱动..."
            local m; m=$(rhel_pkgmgr)
            $m -y install unixODBC unixODBC-devel 2>/dev/null || warn "unixODBC(64位) 安装失败"
            $m -y install unixODBC.i686 2>/dev/null || warn "unixODBC(32位) 安装失败"
            # 32 位驱动复制到 /usr/lib
            local drv; drv=$(off_get el8_el9_el10/libmyodbc3-32bit libmyodbc3-3.51.27.so)
            [ -z "$drv" ] && drv=$(find / -name "libmyodbc3-3.51.27.so" 2>/dev/null | head -1)
            if [ -n "$drv" ]; then
                cp -f "$drv" /usr/lib/libmyodbc3.so 2>/dev/null
                # SONAME 兼容: 老驱动需要 libodbcinst.so.1 / libodbc.so.1
                if [ -f /usr/lib/libodbcinst.so.2 ]; then ln -sf /usr/lib/libodbcinst.so.2 /usr/lib/libodbcinst.so.1; fi
                if [ -f /usr/lib/libodbc.so.2 ]; then ln -sf /usr/lib/libodbc.so.2 /usr/lib/libodbc.so.1; fi
                ln -sf /usr/lib/libmyodbc3.so /usr/lib/libmyodbc3-3.51.27.so 2>/dev/null
            else
                warn "未找到 32 位 MySQL ODBC 驱动, ODBC 连接将失败"
            fi
            ;;
    esac
}

# ---------- 配置 ODBC ----------
rhel_config_odbc() {
    log "配置 /etc/odbc.ini ..."
    mkdir -p /etc
    local drvpath="/usr/lib/libmyodbc3.so"
    case "$SYS_BRANCH" in el8|el9|el10) drvpath="/usr/lib/libmyodbc3.so";; esac
    cat > /etc/odbc.ini <<INI
[tlbbdb]
Driver          = $drvpath
Description     = MyODBC 3.51 Driver DSN
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
    ls /usr/lib/libmyodbc3.so >/dev/null 2>&1 && { info "  [OK] MySQL ODBC 驱动就位 (/usr/lib/libmyodbc3.so)"; ok=$((ok+1)); }
    command -v isql >/dev/null 2>&1 && { info "  [OK] unixODBC isql 可用"; ok=$((ok+1)); }
    local t
    t=$(mysql -uroot -p"${TLBB_DB_PASS}" -N -e "use tlbbdb; show tables;" 2>/dev/null | wc -l)
    [ "$t" -gt 0 ] && { info "  [OK] tlbbdb 含 ${t} 张表"; ok=$((ok+1)); } || warn "  [!!] tlbbdb 无表(需手动导入)"
    info "验证: ${ok}/4 通过"
    [ "$ok" -ge 3 ] && return 0 || return 1
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
    rhel_install_odbc
    rhel_config_odbc
    rhel_verify
}
