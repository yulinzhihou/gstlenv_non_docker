#!/bin/bash
# ============================================================
# TLBB 万能环境安装包 - Debian 系安装模块 (modules/debian/install.sh)
# 覆盖: Ubuntu 12~26 | Debian 10~18
# 数据库: MySQL 5.5/5.6(Ubuntu12-16) | 5.7(Ubuntu18) | 8.0(Ubuntu20+/Debian官方源)
# 32位ODBC: libmyodbc3 3.51.27 (阿里云源 + i386 兼容库)
# ============================================================

# ---------- 配置 apt 国内源 ----------
deb_config_source() {
    # 离线模式: 跳过源配置, 直接使用本地组件
    [ "${TLBB_OFFLINE_MODE:-0}" = "1" ] && { log "离线模式: 跳过 apt 源配置, 使用本地安装包"; return 0; }
    local codename="$SYS_CODENAME"
    local distro="$SYS_ID"
    [ -z "$codename" ] && { warn "无法获取系统代号, 跳过 apt 源替换"; return 0; }

    # 寻找匹配的源文件 (优先 repos/apt 统一源目录)
    local srcfile="" sf
    if [ "$distro" = "ubuntu" ]; then
        for sf in "$TLBB_OFFLINE_DIR/../repos/apt/ubuntu-*-$codename.list" \
                  /opt/tlbb-env-pkg/modules/debian/sources/ubuntu-*-"$codename".list \
                  "$TLBB_OFFLINE_DIR/../modules/debian/sources/ubuntu-*-$codename.list" \
                  "$(dirname "$0")/../debian/sources/ubuntu-*-$codename.list"; do
            [ -f "$sf" ] && { srcfile="$sf"; break; }
        done
    else
        for sf in "$TLBB_OFFLINE_DIR/../repos/apt/debian-*-$codename.list" \
                  "$TLBB_OFFLINE_DIR/../modules/debian/sources/debian-*-$codename.list" \
                  "$(dirname "$0")/../debian/sources/debian-*-$codename.list"; do
            [ -f "$sf" ] && { srcfile="$sf"; break; }
        done
    fi

    if [ -n "$srcfile" ]; then
        log "配置 apt 源: $(basename "$srcfile")"
        mkdir -p /etc/apt/sources.list.d.bak
        cp -r /etc/apt/sources.list.d/* /etc/apt/sources.list.d.bak/ 2>/dev/null
        [ -f /etc/apt/sources.list ] && mv /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
        # 写入 deb 行 (兼容 sources.list 与 deb822)
        cp "$srcfile" /etc/apt/sources.list.d/tlbb.list
        apt-get update >/dev/null 2>&1 || warn "apt update 失败, 请检查网络/源可用性"
    else
        warn "未找到 ${distro}-${codename} 的源模板, 使用系统默认源"
    fi
}

# ---------- 启用 i386 多架构 ----------
deb_add_i386() {
    # 离线模式: 本地启用架构即可, 不联网更新索引
    log "启用 i386 多架构支持..."
    dpkg --add-architecture i386 2>/dev/null
    [ "${TLBB_OFFLINE_MODE:-0}" = "1" ] && return 0
    apt-get update >/dev/null 2>&1 || true
}

# ---------- 安装 32 位兼容库 + unixODBC ----------
deb_install_compat() {
    log "安装 32 位兼容库与 unixODBC..."
    # 离线模式: 从 offline/deb-packages 本地安装
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local debdir="$TLBB_OFFLINE_DIR/deb-packages"
        if [ -d "$debdir" ] && ls "$debdir"/*.deb >/dev/null 2>&1; then
            dpkg -i "$debdir"/*.deb >/dev/null 2>&1 || { DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1 || true; }
            log "离线兼容库安装完成 (来自 $debdir)"
            return 0
        fi
        warn "离线模式未找到兼容库 deb 包, 32 位库与 unixODBC 可能缺失 (可将 deb 放入 offline/deb-packages/)"
        return 0
    fi
    # 现代版本 (16.04+)
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libc6:i386 libstdc++6:i386 libnsl2:i386 libcrypt1:i386 zlib1g:i386 \
        unixodbc:i386 libodbc2:i386 libodbcinst2:i386 \
        >/dev/null 2>&1 || \
    # 回退: 老版本包名不同
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libc6-i386 libstdc++6-i386 unixodbc \
        >/dev/null 2>&1 || warn "32 位库安装不完整, 请检查 apt 源"
    log "32 位兼容库安装完成"
}

# ---------- 配置 MySQL 官方 apt 源 (Debian 10+, 国内镜像) ----------
# Debian 的 mysql-server 元包实为 MariaDB 别名, 要装真 MySQL 必须用官方 apt 源
deb_config_mysql_repo() {
    local codename="$SYS_CODENAME"
    [ -z "$codename" ] && codename=$(lsb_release -cs 2>/dev/null || echo bookworm)
    local dom=""
    for d in "https://mirrors.aliyun.com/mysql" "https://repo.huaweicloud.com/mysql" "https://mirrors.cloud.tencent.com/mysql"; do
        curl -sI --connect-timeout 5 --max-time 8 "$d/apt/debian/" >/dev/null 2>&1 && { dom="$d"; break; }
    done
    [ -z "$dom" ] && dom="https://repo.mysql.com"
    log "配置 MySQL 官方 apt 源: $dom/apt/debian/ ($codename, mysql-8.0)"
    cat > /etc/apt/sources.list.d/mysql.list <<REPO
deb [trusted=yes] ${dom}/apt/debian/ ${codename} mysql-8.0
REPO
    apt-get update >/dev/null 2>&1 || {
        warn "MySQL apt 源更新失败, 该 Debian 代号可能暂无官方包 (移除源, 回退系统包)"
        rm -f /etc/apt/sources.list.d/mysql.list
        apt-get update >/dev/null 2>&1 || true
        return 1
    }
    return 0
}

# ---------- 预置 MySQL debconf 密码 (避免 apt 交互卡死) ----------
deb_preset_mysql_password() {
    local p="$1"
    DEBIAN_FRONTEND=noninteractive debconf-set-selections <<EOF
mysql-server mysql-server/root_password password ${p}
mysql-server mysql-server/root_password_again password ${p}
mysql-community-server mysql-community-server/root-pass password ${p}
mysql-community-server mysql-community-server/re-root-pass password ${p}
EOF
}

# ---------- 安装数据库 ----------
deb_install_db() {
    local mver; mver=$(select_mysql_version)
    log "数据库方案: MySQL ${mver} (可 TLBB_MYSQL_VERSION=51|57|80 覆盖)"
    # 离线模式: 尝试本地 deb 包目录 (offline/deb-packages/mysql<ver>/ 或 deb-packages/)
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local vdir="$TLBB_OFFLINE_DIR/deb-packages/mysql${mver}"
        local debdir="$TLBB_OFFLINE_DIR/deb-packages"
        if [ -d "$vdir" ] && ls "$vdir"/*.deb >/dev/null 2>&1; then
            log "离线安装 MySQL ${mver} (deb: $vdir)..."
            dpkg -i "$vdir"/*.deb >/dev/null 2>&1 || \
            { DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1 || true; }
            return 0
        fi
        if [ -d "$debdir" ] && ls "$debdir"/*.deb >/dev/null 2>&1; then
            log "离线安装数据库 (deb: $debdir)..."
            dpkg -i "$debdir"/*.deb >/dev/null 2>&1 || \
            { DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1 || true; }
            return 0
        fi
        warn "离线模式未找到数据库 deb 包 (offline/deb-packages/mysql${mver}/), 数据库需联网安装"
        warn "提示: 在联网机器上执行 'bash scripts/pack_offline.sh --full <ubuntu|debian>' 获取 deb 放入 offline/deb-packages/mysql${mver}/"
        die "离线数据库包缺失, 安装中止 (或将 offline/deb-packages/mysql${mver}/ 补齐后重试)"
    fi
    deb_preset_mysql_password "$TLBB_DB_PASS"
    case "$SYS_ID:$SYS_VERSION_ID" in
        ubuntu:1[23456]*)
            log "安装 MySQL 5.5/5.6 (Ubuntu 系统源自带真 MySQL)..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server mysql-client \
                >/dev/null 2>&1 || die "MySQL 安装失败"
            ;;
        ubuntu:18*)
            log "安装 MySQL 5.7 (Ubuntu 18 系统源自带真 MySQL)..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server mysql-client \
                >/dev/null 2>&1 || die "MySQL 5.7 安装失败"
            ;;
        ubuntu:*)
            log "安装 MySQL 8.0 (Ubuntu 20+ 系统源自带真 MySQL, 非 MariaDB)..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server mysql-client \
                >/dev/null 2>&1 || die "MySQL 8.0 安装失败"
            ;;
        debian:*)
            log "安装 MySQL 8.0 (Debian 官方 apt 源, 避开 MariaDB 元包)..."
            if deb_config_mysql_repo; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-community-server mysql-community-client \
                    >/dev/null 2>&1 || \
                { warn "MySQL 官方包安装失败(该 Debian 代号可能暂无官方包), 尝试系统源 mysql-server"; \
                  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server mysql-client >/dev/null 2>&1 || die "数据库安装失败"; }
            else
                warn "MySQL 官方 apt 源不可用, 该 Debian 代号需使用离线包 (offline/deb-packages/mysql80/)"
                die "数据库安装中止, 请先通过 pack_offline.sh 生成对应离线包"
            fi
            ;;
        *)
            warn "未知 Debian 系系统, 尝试系统源 mysql-server"
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server mysql-client \
                >/dev/null 2>&1 || die "MySQL 安装失败"
            ;;
    esac
}

deb_start_db() {
    log "启动数据库 (MySQL $(select_mysql_version))..."
    service mysql start >/dev/null 2>&1 || service mysqld start >/dev/null 2>&1 || \
    systemctl start mysql >/dev/null 2>&1 || systemctl start mysqld >/dev/null 2>&1 || true
    sleep 4
    local i
    for i in $(seq 1 20); do
        mysqladmin ping >/dev/null 2>&1 && { log "数据库已就绪"; return 0; }
        sleep 2
    done
    warn "数据库未完全就绪, 继续尝试..."
}

# ---------- 建库导入 ----------
deb_setup_db() {
    local mver; mver=$(select_mysql_version)
    local sql_dir
    sql_dir=$(off_get sql tlbbdb.sql 2>/dev/null)
    sql_dir=$(dirname "$sql_dir" 2>/dev/null || echo "$TLBB_OFFLINE_DIR/sql")
    local tlbbdb="$sql_dir/tlbbdb.sql" web="$sql_dir/web.sql"
    [ -f "$tlbbdb" ] || tlbbdb=$(find / -name "tlbbdb.sql" 2>/dev/null | head -1)
    [ -f "$web" ] || web=$(find / -name "web.sql" 2>/dev/null | head -1)

    log "配置 MySQL ${mver} 账号并建库..."
    case "$mver" in
        80)
            # MySQL 8.0: root 走 auth_socket/临时密码, 需改 native 认证并卸载密码强度校验
            # 先以 auth_socket 方式(sudo mysql)重置 root
            mysql -uroot -e "UNINSTALL COMPONENT 'file://component_validate_password';" 2>/dev/null
            mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';" 2>/dev/null || \
            sudo -n mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';" 2>/dev/null
            # Debian 官方包首启可能生成临时密码
            local tmp_pw
            tmp_pw=$(grep -a "temporary password" /var/log/mysql/error.log 2>/dev/null | tail -1 | sed 's/.*: //')
            [ -z "$tmp_pw" ] && tmp_pw=$(grep -a "temporary password" /var/log/mysqld.log 2>/dev/null | tail -1 | sed 's/.*: //')
            [ -n "$tmp_pw" ] && mysql -uroot -p"$tmp_pw" --connect-expired-password \
                -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';" 2>/dev/null
            mysql -uroot -p"${TLBB_DB_PASS}" -e "
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
FLUSH PRIVILEGES;" 2>/dev/null || warn "MySQL 8.0 账号配置失败, 请手动检查 root 认证方式"
            ;;
        57)
            # MySQL 5.7 (Ubuntu 18): root 走 auth_socket
            mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';" 2>/dev/null || \
            sudo -n mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}';" 2>/dev/null
            mysql -uroot -p"${TLBB_DB_PASS}" -e "
CREATE USER IF NOT EXISTS 'gs'@'%' IDENTIFIED WITH mysql_native_password BY '${TLBB_MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;
FLUSH PRIVILEGES;" 2>/dev/null || warn "MySQL 5.7 账号配置失败"
            ;;
        *)
            # 老 MySQL (5.5/5.6): root 默认空密码走 Password 列
            mysql -uroot -e "use mysql; update user set Password=PASSWORD('${TLBB_DB_PASS}') where User='root'; FLUSH PRIVILEGES;" 2>/dev/null
            mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${TLBB_DB_PASS}' WITH GRANT OPTION;" 2>/dev/null
            mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'gs'@'%' IDENTIFIED BY '${TLBB_MYSQL_PASSWORD}' WITH GRANT OPTION;" 2>/dev/null
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

# ---------- 安装 ODBC 驱动 ----------
deb_install_odbc() {
    log "部署 32 位 MySQL ODBC 3.51 驱动..."
    local drv
    drv=$(find / -name "libmyodbc3-3.51.27.so" 2>/dev/null | head -1)
    if [ -z "$drv" ]; then
        # 从离线目录解压
        local m
        m=$(off_get deb-common/libmyodbc3-32bit libmyodbc3-3.51.27.so)
        [ -n "$m" ] && drv="$m"
    fi
    if [ -n "$drv" ]; then
        mkdir -p /usr/lib/i386-linux-gnu
        cp -f "$drv" /usr/lib/i386-linux-gnu/libmyodbc3.so
        cp -f "$(dirname "$drv")/libmyodbc3S.so" /usr/lib/i386-linux-gnu/libmyodbc3S.so 2>/dev/null
        # SONAME 兼容: 老驱动需要 libodbcinst.so.1 (现代 unixODBC 提供 .so.2)
        if [ -f /usr/lib/i386-linux-gnu/libodbcinst.so.2.0.0 ]; then
            ln -sf /usr/lib/i386-linux-gnu/libodbcinst.so.2.0.0 /usr/lib/i386-linux-gnu/libodbcinst.so.1
        fi
        if [ -f /usr/lib/i386-linux-gnu/libodbc.so.2.0.0 ]; then
            ln -sf /usr/lib/i386-linux-gnu/libodbc.so.2.0.0 /usr/lib/i386-linux-gnu/libodbc.so.1
        fi
        log "驱动就位: /usr/lib/i386-linux-gnu/libmyodbc3.so"
    else
        warn "未找到 32 位 MySQL ODBC 驱动, ODBC 连接将失败"
    fi
}

# ---------- 配置 ODBC ----------
deb_config_odbc() {
    log "配置 /etc/odbc.ini ..."
    # 驱动自动检测: 64 位 libmaodbc (MySQL8 ODBC) → 64 位 libmyodbc → 32 位 libmyodbc3
    local drvpath=""
    for c in /usr/lib/x86_64-linux-gnu/libmaodbc.so /usr/lib/x86_64-linux-gnu/libmyodbc.so /usr/lib/i386-linux-gnu/libmyodbc3.so; do
        [ -f "$c" ] && { drvpath="$c"; break; }
    done
    [ -z "$drvpath" ] && drvpath="/usr/lib/i386-linux-gnu/libmyodbc3.so"
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

[MySQL ODBC 3.51 Driver]
Driver=$drvpath
Setup=/usr/lib/i386-linux-gnu/libmyodbc3S.so
UsageCount=1
INI
    log "ODBC 配置完成"
}

# ---------- 验证 ----------
deb_verify() {
    log "验证安装结果..."
    local ok=0
    mysqladmin ping >/dev/null 2>&1 && { info "  [OK] 数据库运行中"; ok=$((ok+1)); } || warn "  [!!] 数据库未运行"
    ls /usr/lib/i386-linux-gnu/libmyodbc3.so >/dev/null 2>&1 && { info "  [OK] 32 位 ODBC 驱动就位"; ok=$((ok+1)); }
    # 驱动依赖完整性检查
    if command -v ldd >/dev/null 2>&1; then
        local missing
        missing=$(ldd /usr/lib/i386-linux-gnu/libmyodbc3.so 2>/dev/null | grep -c "not found")
        [ "$missing" = "0" ] && { info "  [OK] 驱动依赖完整"; ok=$((ok+1)); } || warn "  [!!] 驱动缺少 ${missing} 个依赖"
    fi
    local t
    t=$(mysql -uroot -p"${TLBB_DB_PASS}" -N -e "use tlbbdb; show tables;" 2>/dev/null | wc -l)
    [ "$t" -gt 0 ] && { info "  [OK] tlbbdb 含 ${t} 张表"; ok=$((ok+1)); } || warn "  [!!] tlbbdb 无表"
    info "验证: ${ok}/4 通过"
    [ "$ok" -ge 3 ] && return 0 || return 1
}

# ---------- Debian 主流程 ----------
deb_install() {
    ask_dbpass
    deb_config_source
    deb_add_i386
    deb_install_compat
    deb_install_db
    deb_start_db
    deb_setup_db
    deb_install_odbc
    deb_config_odbc
    deb_verify
}
