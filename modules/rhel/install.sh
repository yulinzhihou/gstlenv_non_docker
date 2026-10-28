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
            for r in "$rdir"/*.rpm; do rpm -ivh "$r" --nodeps --force >/dev/null 2>&1; done
            log "离线兼容库安装完成 (来自 $rdir)"
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

# ---------- 配置 MySQL 官方 yum 源 (国内镜像) ----------
# 优先级: 阿里云 → 华为云 → 腾讯云; 全部不可达时使用 MySQL 官方源
rhel_config_mysql_repo() {
    # $1: 57|80
    local ver="$1" rel="${SYS_BRANCH#el}"
    [ -z "$rel" ] && rel="7"
    local base=""
    for dom in "https://mirrors.aliyun.com/mysql" "https://repo.huaweicloud.com/mysql" "https://mirrors.cloud.tencent.com/mysql"; do
        if curl -sI --connect-timeout 5 --max-time 8 "$dom/" >/dev/null 2>&1 || wget -T 8 -O /dev/null -q "$dom/" 2>/dev/null; then
            base="$dom"; break
        fi
    done
    [ -z "$base" ] && base="http://repo.mysql.com"
    log "MySQL ${ver} yum 源: $base"
    cat > /etc/yum.repos.d/mysql-community.repo <<REPO
# MySQL Community Server ${ver} (国内镜像, 由 TLBB 万能环境安装器生成)
[mysql${ver}-community]
name=MySQL ${ver} Community Server
baseurl=${base}/yum/mysql-${ver}-community/el/${rel}/\$basearch/
enabled=1
gpgcheck=0
REPO
    # 兼容 8.0 依赖的 mysql-connectors 公共源 (部分包在 connectors/common 中)
    if [ "$ver" = "80" ]; then
        cat > /etc/yum.repos.d/mysql-tools.repo <<REPO
[mysql-tools-community]
name=MySQL Tools Community
baseurl=${base}/yum/mysql-tools-community/el/${rel}/\$basearch/
enabled=1
gpgcheck=0
REPO
    fi
    local m; m=$(rhel_pkgmgr)
    $m clean all >/dev/null 2>&1
    $m makecache >/dev/null 2>&1 || warn "MySQL 源 makecache 失败, 请检查网络"
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
            rpm -ivh "$rdir"/*.rpm --nodeps --force >/dev/null 2>&1 || \
                { warn "数据库 rpm 安装失败, 尝试依赖补齐"; rpm -ivh "$rdir"/*.rpm >/dev/null 2>&1 || die "离线数据库安装失败"; }
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
            log "安装 MySQL 5.7 (国内镜像源)..."
            rhel_config_mysql_repo 57
            rhel_pkg_install mysql-community-server || die "MySQL 5.7 安装失败"
            ;;
        80)
            log "安装 MySQL 8.0 (国内镜像源)..."
            rhel_config_mysql_repo 80
            rhel_pkg_install mysql-community-server || die "MySQL 8.0 安装失败"
            ;;
        *) die "不支持的 MySQL 版本: $mver (可选 51|57|80)";;
    esac
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
# MySQL 5.7+ 首次启动生成临时 root 密码 (写入 /var/log/mysqld.log)
# 脚本自动提取并重置为 TLBB_DB_PASS, 同时卸载 validate_password 强度校验
rhel_handle_first_boot() {
    local mver; mver=$(select_mysql_version)
    [ "$mver" = "51" ] && return 0
    local tmp_pw=""
    # 从日志提取临时密码
    tmp_pw=$(grep -a "temporary password" /var/log/mysqld.log 2>/dev/null | tail -1 | sed 's/.*: //')
    if [ -z "$tmp_pw" ]; then
        # 无临时密码(已初始化过): 直接尝试无密/空密
        mysql -uroot -e "SELECT 1;" >/dev/null 2>&1 && return 0
        warn "未找到 MySQL 临时密码, 尝试空密码登录"
        return 0
    fi
    log "检测到 MySQL 首次临时密码, 正在重置为 ${TLBB_DB_PASS} ..."
    mysql -uroot -p"$tmp_pw" --connect-expired-password \
        -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}'; FLUSH PRIVILEGES;" 2>/dev/null || \
    mysql -uroot -p"$tmp_pw" \
        -e "SET PASSWORD = PASSWORD('${TLBB_DB_PASS}'); FLUSH PRIVILEGES;" 2>/dev/null || \
        { warn "临时密码重置失败, 请手动检查 /var/log/mysqld.log"; }
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
            mysql -uroot -p"${TLBB_DB_PASS}" -e "
UNINSTALL COMPONENT 'file://component_validate_password' 2>/dev/null;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
FLUSH PRIVILEGES;" 2>/dev/null || \
            { warn "MySQL 8.0 账号配置失败, 尝试本地无密登录"; mysql -uroot -e "
UNINSTALL COMPONENT 'file://component_validate_password' 2>/dev/null;
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
