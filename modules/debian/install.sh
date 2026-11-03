#!/bin/bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: Debian 系安装模块 (Ubuntu 12~26 | Debian 10~18, 配置 apt 源 + MySQL + ODBC)

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
    # Debian/Ubuntu apt 无 MySQL 8.4 包 (仅 8.0), 预置 84 时按 8.0 处理
    [ "$mver" = "84" ] && { warn "Debian/Ubuntu apt 无 MySQL 8.4 包, 按 8.0 安装"; mver="80"; }
    log "数据库方案: MySQL ${mver} (可 TLBB_MYSQL_VERSION=51|57|80|84 覆盖)"
    # 离线模式: 优先版本专属目录 (v5: debian11/12 用 MySQL 官方 apt mysql-community 全套)
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local subdir=""
        case "$SYS_BRANCH" in
            ubuntu) subdir="deb-packages/ubuntu${SYS_VERSION_ID%%.*}" ;;
            debian) subdir="deb-packages/debian${SYS_VERSION_ID%%.*}" ;;
        esac
        if [ -n "$subdir" ] && [ -d "$TLBB_OFFLINE_DIR/$subdir" ] && ls "$TLBB_OFFLINE_DIR/$subdir"/*.deb >/dev/null 2>&1; then
            log "离线安装 MySQL 8.0 (deb 版本目录: $subdir)..."
            # 同目录 dpkg -i 一次性解析内部依赖; 外部依赖 (libmecab2/libatomic1) 已随包入库
            DEBIAN_FRONTEND=noninteractive dpkg -i "$TLBB_OFFLINE_DIR/$subdir"/*.deb >/dev/null 2>&1 || \
            { DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1 || true; }
            return 0
        fi
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
        warn "离线模式未找到数据库 deb 包 (offline/deb-packages/mysql${mver}/ 或版本子目录), 数据库需联网安装"
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
    local tlbbdb="$sql_dir/tlbbdb.sql" web="$sql_dir/web.sql" t10="$sql_dir/tlbbdb_10.sql"
    [ -f "$tlbbdb" ] || tlbbdb=$(find / -name "tlbbdb.sql" 2>/dev/null | head -1)
    [ -f "$web" ] || web=$(find / -name "web.sql" 2>/dev/null | head -1)
    [ -f "$t10" ] || t10=$(find / -name "tlbbdb_10.sql" 2>/dev/null | head -1)

    # 数据库结构: 3库(新端 tlbbdb_10+tlbbdb_main+web) / 2库(怀旧 tlbbdb+web); 8.0 交互选择, 其余固定 2 库
    local dblayout="${TLBB_DB_LAYOUT:-3}"
    local main_db="tlbbdb" need_t10=0
    if [ "$mver" = "80" ] && [ "$dblayout" = "3" ]; then
        main_db="tlbbdb_main"; need_t10=1
    fi

    log "配置 MySQL ${mver} 账号并建库 (${dblayout} 库结构, 主库 ${main_db})..."
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
FLUSH PRIVILEGES;" 2>/dev/null || warn "MySQL 8.0 账号配置失败, 请手动检查 root 认证方式"
            # 按 2/3 库结构建库
            if [ "$need_t10" = "1" ]; then
                mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb_main CHARACTER SET utf8; CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8; CREATE DATABASE IF NOT EXISTS tlbbdb_10 CHARACTER SET utf8;" 2>/dev/null
            else
                mysql -uroot -p"${TLBB_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS tlbbdb CHARACTER SET utf8; CREATE DATABASE IF NOT EXISTS web CHARACTER SET utf8;" 2>/dev/null
            fi
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
        log "导入初始数据 (${dblayout} 库结构, 主库 ${main_db}, 目标库已先建好并显式指定导入)..."
        if [ "$main_db" = "tlbbdb" ]; then
            mysql -uroot -p"${TLBB_DB_PASS}" "$main_db" < "$tlbbdb" 2>/dev/null && log "tlbbdb 导入成功" || warn "tlbbdb 导入失败"
        else
            # 3 库模式: 主库物理名为 tlbbdb_main, 改写 tlbbdb.sql 的 CREATE DATABASE/USE 头后导入
            sed 's/CREATE DATABASE IF NOT EXISTS tlbbdb\b/CREATE DATABASE IF NOT EXISTS tlbbdb_main/g; s/^USE tlbbdb;/USE tlbbdb_main;/g' "$tlbbdb" | mysql -uroot -p"${TLBB_DB_PASS}" "$main_db" 2>/dev/null && log "tlbbdb_main 导入成功" || warn "tlbbdb_main 导入失败"
        fi
        mysql -uroot -p"${TLBB_DB_PASS}" web < "$web" 2>/dev/null && log "web 导入成功" || warn "web 导入失败"
        if [ "$need_t10" = "1" ] && [ -f "$t10" ]; then
            mysql -uroot -p"${TLBB_DB_PASS}" tlbbdb_10 < "$t10" 2>/dev/null && log "tlbbdb_10 导入成功" || warn "tlbbdb_10 导入失败"
        fi
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
    # 按 2/3 库结构决定主库名与是否含 tlbbdb_10 (与建库一致)
    local mver; mver=$(select_mysql_version)
    local dblayout="${TLBB_DB_LAYOUT:-3}"
    local main_db="tlbbdb" has_t10=0
    if [ "$mver" = "80" ] && [ "$dblayout" = "3" ]; then
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
    local main_db="tlbbdb"
    [ "$(select_mysql_version)" = "80" ] && [ "${TLBB_DB_LAYOUT:-3}" = "3" ] && main_db="tlbbdb_main"
    t=$(mysql -uroot -p"${TLBB_DB_PASS}" -N -e "use ${main_db}; show tables;" 2>/dev/null | wc -l)
    [ "$t" -gt 0 ] && { info "  [OK] ${main_db} 含 ${t} 张表"; ok=$((ok+1)); } || warn "  [!!] ${main_db} 无表"
    # 可选组件验证 (仅当对应命令存在; 不纳入 4 项基础分, 纯状态展示)
    command -v nginx >/dev/null 2>&1 && { nginx -v >/dev/null 2>&1 && info "  [OK] 可选组件 nginx: $(nginx -v 2>&1 | head -1)" || warn "  [!!] 可选组件 nginx 验证失败"; }
    command -v php >/dev/null 2>&1 && { php -v >/dev/null 2>&1 && info "  [OK] 可选组件 PHP: $(php -v 2>/dev/null | head -1)" || warn "  [!!] 可选组件 PHP 验证失败"; }
    command -v redis-server >/dev/null 2>&1 && { redis-cli ping >/dev/null 2>&1 && info "  [OK] 可选组件 Redis 运行中 (127.0.0.1:6379)" || warn "  [!!] 可选组件 Redis 未运行"; }
    info "验证: ${ok}/4 通过"
    [ "$ok" -ge 3 ] && return 0 || return 1
}

# ---------- 安装 Redis (billing/GM 工具依赖) ----------
deb_install_redis() {
    if command -v redis-server >/dev/null 2>&1 || dpkg -s redis-server >/dev/null 2>&1; then
        log "Redis 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        # 离线: 检查 deb-packages 下的 redis deb (可选)
        if ls "$TLBB_OFFLINE_DIR"/deb-packages/redis*.deb >/dev/null 2>&1; then
            dpkg -i "$TLBB_OFFLINE_DIR"/deb-packages/redis*.deb >/dev/null 2>&1 && \
                log "离线 redis deb 安装完成" || warn "离线 redis deb 安装失败"
        else
            warn "离线包未含 redis deb, 跳过 (billing 验证可能需要 redis)"
        fi
    else
        apt-get -y install redis-server >/dev/null 2>&1 || warn "redis 安装失败 (可选组件)"
    fi
    command -v redis-server >/dev/null 2>&1 || return 0
    systemctl enable --now redis-server >/dev/null 2>&1 || \
        systemctl enable --now redis >/dev/null 2>&1 || \
        { redis-server --daemonize yes >/dev/null 2>&1 || warn "redis 启动失败"; }
    sleep 2
    local rp="${TLBB_REDIS_PASSWORD:?请先初始化服务凭据}"
    if redis-cli -a "$rp" ping >/dev/null 2>&1; then
        log "Redis 密码认证通过: 127.0.0.1:6379"
    else
        redis-cli CONFIG SET requirepass "$rp" >/dev/null 2>&1 && \
            redis-cli -a "$rp" ping >/dev/null 2>&1 && log "Redis 密码已设置" || \
            warn "Redis 密码设置失败, 请检查服务配置"
    fi
    local rconf=$(find /etc -name "redis.conf" 2>/dev/null | head -1)
    if [ -n "$rconf" ]; then
        grep -q "^requirepass" "$rconf" && \
            sed -i "s/^requirepass.*/requirepass ${rp}/" "$rconf" || \
            echo "requirepass ${rp}" >> "$rconf"
    fi
    log "Redis 配置完成: 127.0.0.1:6379"
}

# ---------- 可选组件: nginx (系统源最新版) ----------
deb_install_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        log "Nginx 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local nfile; nfile=$(find "$TLBB_OFFLINE_DIR/deb-packages" -maxdepth 2 -name "nginx*.deb" 2>/dev/null | head -1)
        if [ -n "$nfile" ]; then
            dpkg -i "$(dirname "$nfile")"/nginx*.deb >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1
            command -v nginx >/dev/null 2>&1 && log "离线 nginx deb 安装完成" || warn "离线 nginx deb 安装失败"
        else
            warn "离线包未含 nginx deb, 跳过 (可选组件, 在线模式可装)"
        fi
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y nginx >/dev/null 2>&1 || \
            { warn "nginx 安装失败 (源中无可用包或网络异常, 已跳过)"; return 0; }
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
deb_install_php() {
    if command -v php >/dev/null 2>&1; then
        log "PHP 已安装, 跳过安装"
    elif [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        local pfile; pfile=$(find "$TLBB_OFFLINE_DIR/deb-packages" -maxdepth 2 -name "php*.deb" 2>/dev/null | head -1)
        if [ -n "$pfile" ]; then
            dpkg -i "$(dirname "$pfile")"/php*.deb >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -f >/dev/null 2>&1
            command -v php >/dev/null 2>&1 && log "离线 php deb 安装完成" || warn "离线 php deb 安装失败"
        else
            warn "离线包未含 php deb, 跳过 (可选组件, 在线模式可装)"
        fi
    else
        # 新系统源为 php + php-fpm (8.x), 老 Ubuntu (12-16) 为 php5 + php5-fpm
        DEBIAN_FRONTEND=noninteractive apt-get install -y php php-fpm >/dev/null 2>&1 || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y php5 php5-fpm >/dev/null 2>&1 || \
            { warn "php 安装失败 (源中无可用包或网络异常, 已跳过)"; return 0; }
    fi
    command -v php >/dev/null 2>&1 || return 0
    # 安装成功验证
    if php -v >/dev/null 2>&1; then
        log "PHP 安装成功并验证通过: $(php -v 2>/dev/null | head -1)"
    else
        warn "PHP 已安装但验证失败 (php -v 异常, 请检查依赖是否完整)"
    fi
    # 启动 php-fpm (新系统为 php-fpm, 老 Ubuntu 为 php5-fpm; 无 systemctl 时用 service)
    systemctl enable --now php-fpm >/dev/null 2>&1 || \
    systemctl enable --now php5-fpm >/dev/null 2>&1 || \
    service php5-fpm start >/dev/null 2>&1 || service php-fpm start >/dev/null 2>&1 || true
}

# ---------- 可选组件交互安装 (nginx/php/redis, 安装完 MySQL 后询问, 默认 no) ----------
deb_install_optional() {
    log "可选组件询问 (nginx/php/redis, 直接回车=不安装)..."
    [ "$(ask_optional_component nginx "Web 服务器, 用于 GM 工具/网站 (将安装当前系统源最新版)" TLBB_OPT_NGINX)" = "1" ] && deb_install_nginx
    [ "$(ask_optional_component php "PHP 运行时, 配合 Nginx 提供网站服务 (将安装当前系统源最新版)" TLBB_OPT_PHP)" = "1" ] && deb_install_php
    [ "$(ask_optional_component redis "Redis 内存数据库, billing/GM 工具依赖, 使用持久化随机密码 (将安装当前系统源最新版)" TLBB_OPT_REDIS)" = "1" ] && deb_install_redis
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
    deb_install_optional   # nginx/php/redis 可选组件 (交互询问, 默认不安装)
    deb_install_odbc
    deb_config_odbc
    deb_verify
}
