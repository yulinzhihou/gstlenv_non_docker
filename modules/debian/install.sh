#!/bin/bash
# ============================================================
# TLBB 万能环境安装包 - Debian 系安装模块 (modules/debian/install.sh)
# 覆盖: Ubuntu 12~26 | Debian 10~18
# 已验证: Ubuntu 24.04 全链路 (阿里云源 + i386 + MariaDB + 32位ODBC)
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

# ---------- 安装数据库 ----------
deb_install_db() {
    # 离线模式: 尝试本地 deb 包目录 (offline/deb-packages/ 若存在), 否则提示
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local debdir="$TLBB_OFFLINE_DIR/deb-packages"
        if [ -d "$debdir" ] && ls "$debdir"/*.deb >/dev/null 2>&1; then
            log "离线安装数据库 (deb 包: $debdir)..."
            dpkg -i "$debdir"/*.deb >/dev/null 2>&1 || \
            { DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1 || true; }
        else
            warn "离线模式未找到数据库 deb 包 (offline/deb-packages/), 数据库需联网安装"
            warn "提示: 在联网机器上执行 'apt-get download mariadb-server' 等命令获取 deb 放入 offline/deb-packages/"
            die "离线数据库包缺失, 安装中止 (或将 offline/deb-packages/ 补齐后重试)"
        fi
        return 0
    fi
    log "安装 MariaDB/MySQL..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mariadb-server mariadb-client \
        >/dev/null 2>&1 || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client \
        >/dev/null 2>&1 || die "数据库安装失败"
}

deb_start_db() {
    log "启动数据库..."
    service mariadb start >/dev/null 2>&1 || service mysql start >/dev/null 2>&1 || \
    systemctl start mariadb >/dev/null 2>&1 || true
    sleep 4
    local i
    for i in $(seq 1 15); do
        mysqladmin ping >/dev/null 2>&1 && { log "数据库已就绪"; return 0; }
        sleep 2
    done
    warn "数据库未完全就绪"
}

# ---------- 建库导入 ----------
deb_setup_db() {
    local sql_dir
    local tlbbdb="" web=""
    tlbbdb=$(find / -name "tlbbdb.sql" 2>/dev/null | head -1)
    web=$(find / -name "web.sql" 2>/dev/null | head -1)

    log "配置数据库账号并建库..."
    # 现代 MariaDB/MySQL5.7+ (root 走 unix_socket 或 caching_sha2, 需改认证并建游戏账号)
    mysql -uroot <<SQL 2>/dev/null
CREATE DATABASE IF NOT EXISTS tlbbdb;
CREATE DATABASE IF NOT EXISTS web;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'tlbb'@'%' IDENTIFIED BY '${TLBB_DB_PASS}';
GRANT ALL PRIVILEGES ON tlbbdb.* TO 'tlbb'@'%';
GRANT ALL PRIVILEGES ON web.* TO 'tlbb'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TLBB_DB_PASS}' 2>/dev/null;
FLUSH PRIVILEGES;
SQL
    # 老 MySQL (5.5/5.6, Ubuntu 12~15) 兜底: 直接改 Password 列
    mysql -uroot -e "use mysql; update user set Password=PASSWORD('${TLBB_DB_PASS}') where User='root'; FLUSH PRIVILEGES;" 2>/dev/null
    # 建库 (现代版已在上面建好, 老版这里补建)
    mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb; CREATE DATABASE IF NOT EXISTS web;" 2>/dev/null
    if [ -n "$tlbbdb" ] && [ -n "$web" ]; then
        mysql -uroot -p"${TLBB_DB_PASS}" tlbbdb < "$tlbbdb" >/dev/null 2>&1 && log "tlbbdb 导入成功"
        mysql -uroot -p"${TLBB_DB_PASS}" web < "$web" >/dev/null 2>&1 && log "web 导入成功"
    else
        warn "未找到离线 SQL, 请手动导入 offline/sql/"
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
    local drvpath="/usr/lib/i386-linux-gnu/libmyodbc3.so"
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
