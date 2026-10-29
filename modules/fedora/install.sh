#!/bin/bash
# ============================================================
# GS游享网 · 天龙八部万能安装器 - Fedora 34~38 安装模块
# ------------------------------------------------------------
# Fedora 特点:
#   - 官方仓库默认 MariaDB (无 MySQL 包), 且无 MySQL 官方 yum 仓库
#   - 离线方案: MySQL 8.0 官方通用 Linux 二进制 tarball (免仓库依赖)
#   - 辅助组件 (32位库/ODBC/Redis) 从 Fedora archive 仓库下载 rpm
#   - 在线方案: 配置阿里云 fedora 镜像源 + archive 仓库兜底
# ============================================================

# ---------- 配置国内源 (在线模式) ----------
fed_config_source() {
    [ "${TLBB_OFFLINE_MODE:-0}" = "1" ] && return 0
    log "配置 Fedora 国内源 (阿里云)..."
    local ver="${SYS_VERSION_ID:-34}"
    local repos=(fedora fedora-updates fedora-modular fedora-updates-modular)
    for r in "${repos[@]}"; do
        cat > "/etc/yum.repos.d/$r.repo" <<REPO
[$r]
name=Fedora ${ver} - ${r}
baseurl=https://mirrors.aliyun.com/fedora/releases/${ver}/Everything/x86_64/os/
enabled=1
gpgcheck=0
REPO
    done
    dnf makecache >/dev/null 2>&1 || true
}

# ---------- 离线完整性检查 (install.sh check_offline_complete 分支) ----------
fed_check_offline() {
    local d="$TLBB_OFFLINE_DIR/rpm-packages/fedora"
    local need=""
    [ -f "$d/mysql80/mysql-8.0"*.tar.xz ] 2>/dev/null || need="MySQL 通用二进制 (fedora/mysql80/)"
    ls "$d/compat"/*.rpm >/dev/null 2>&1 || need="$need compat"
    ls "$d/odbc"/*.rpm >/dev/null 2>&1 || need="$need odbc"
    ls "$d/redis"/*.rpm >/dev/null 2>&1 || need="$need redis"
    [ -n "$need" ] && warn "Fedora 离线缺少: $need"
}

# ---------- 安装 32 位兼容库 (TLBB 端进程依赖) ----------
fed_install_compat() {
    log "安装 32 位兼容库 (Fedora i686)..."
    local d="$TLBB_OFFLINE_DIR/rpm-packages/fedora/compat"
    if ls "$d"/*.rpm >/dev/null 2>&1; then
        dnf install -y --nogpgcheck "$d"/*.rpm >/dev/null 2>&1 || \
        rpm -ivh --nodeps "$d"/*.rpm >/dev/null 2>&1 || \
        warn "部分 32 位库安装失败 (TLBB 端可能需要, 64位端可跳过)"
    else
        # 在线兜底
        dnf install -y glibc.i686 libstdc++.i686 ncurses-libs.i686 libnsl.i686 zlib.i686 >/dev/null 2>&1 || true
    fi
}

# ---------- 安装 MySQL 8.0 (通用二进制 tarball) ----------
fed_install_db() {
    local tb
    tb=$(ls "$TLBB_OFFLINE_DIR/rpm-packages/fedora/mysql80/mysql-8.0"*.tar.xz 2>/dev/null | head -1)
    if [ -z "$tb" ]; then
        if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
            die "离线模式缺少 MySQL 通用二进制 (offline/rpm-packages/fedora/mysql80/), 请补齐后重试"
        fi
        # 在线: 下载官方通用二进制
        log "在线下载 MySQL 8.0 通用二进制..."
        mkdir -p "$TLBB_OFFLINE_DIR/rpm-packages/fedora/mysql80"
        local url
        for url in "https://cdn.mysql.com/Downloads/MySQL-8.0/mysql-8.0.36-linux-glibc2.17-x86_64.tar.xz" \
                   "https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.36-linux-glibc2.17-x86_64.tar.xz"; do
            curl -fsSL --connect-timeout 15 --max-time 900 "$url" -o "$TLBB_OFFLINE_DIR/rpm-packages/fedora/mysql80/mysql-8.0.36-linux-glibc2.17-x86_64.tar.xz" 2>/dev/null && { tb="$TLBB_OFFLINE_DIR/rpm-packages/fedora/mysql80/mysql-8.0.36-linux-glibc2.17-x86_64.tar.xz"; break; }
        done
        [ -z "$tb" ] && die "MySQL 通用二进制下载失败"
    fi

    log "部署 MySQL 8.0 通用二进制 ($(basename "$tb"))..."
    tar xf "$tb" -C /usr/local
    local dir
    dir=$(ls -d /usr/local/mysql-* 2>/dev/null | grep -v mysql-server | head -1)
    [ -z "$dir" ] && die "解压失败, 未找到 mysql-* 目录"
    [ -e /usr/local/mysql ] && mv /usr/local/mysql /usr/local/mysql.bak.$(date +%s)
    mv "$dir" /usr/local/mysql

    # 用户与目录
    id mysql >/dev/null 2>&1 || useradd -r -g mysql -s /bin/false mysql 2>/dev/null || groupadd -r mysql && useradd -r -g mysql -s /bin/false mysql 2>/dev/null
    mkdir -p /var/lib/mysql /var/log/mysql /var/run/mysqld
    chown -R mysql:mysql /usr/local/mysql /var/lib/mysql /var/log/mysql /var/run/mysqld 2>/dev/null

    # 初始化 (8.0: --initialize-insecure, root 空密码)
    if [ ! -d /var/lib/mysql/mysql ]; then
        log "初始化 MySQL 数据目录 (root 空密码, 后续设置)..."
        /usr/local/mysql/bin/mysqld --initialize-insecure --user=mysql \
            --basedir=/usr/local/mysql --datadir=/var/lib/mysql >/dev/null 2>&1 || \
        die "MySQL 初始化失败, 请查看 /var/log/mysql/mysqld.log"
    fi

    # 配置 my.cnf
    cat > /etc/my.cnf <<CNF
[mysqld]
basedir=/usr/local/mysql
datadir=/var/lib/mysql
socket=/var/run/mysqld/mysqld.sock
pid-file=/var/run/mysqld/mysqld.pid
port=${TL_MYSQL_PORT:-3306}
log-error=/var/log/mysql/mysqld.log
user=mysql
CNF

    # systemd 服务
    cat > /etc/systemd/system/mysql-generic.service <<UNIT
[Unit]
Description=MySQL Community Server 8.0 (Generic Binary)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/mysql/bin/mysqld --user=mysql
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable mysql-generic >/dev/null 2>&1
    systemctl restart mysql-generic >/dev/null 2>&1
    # 通用二进制启动路径 /var/run/mysqld 权限
    chown mysql:mysql /var/run/mysqld 2>/dev/null

    # 等待就绪
    local i
    for i in $(seq 1 30); do
        /usr/local/mysql/bin/mysqladmin ping >/dev/null 2>&1 && break
        sleep 2
    done
    /usr/local/mysql/bin/mysqladmin ping >/dev/null 2>&1 || die "MySQL 启动失败"

    # 设置 root 密码 + gs 用户 (大小写兼容, 密码默认对齐 gstlenv)
    local pass="${TLBB_DB_PASS:-123456}"
    /usr/local/mysql/bin/mysql -uroot <<SQL 2>/dev/null || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${pass}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${pass}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'gs'@'localhost' IDENTIFIED BY '${pass}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'localhost' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'gs'@'127.0.0.1' IDENTIFIED BY '${pass}';
GRANT ALL PRIVILEGES ON *.* TO 'gs'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

    # PATH 软链
    for b in mysql mysqladmin mysqldump mysqlcheck; do
        ln -sf /usr/local/mysql/bin/$b /usr/local/bin/$b
    done
    ln -sf /usr/local/mysql/bin/mysql /usr/bin/mysql 2>/dev/null
    ln -sf /usr/local/mysql/bin/mysqladmin /usr/bin/mysqladmin 2>/dev/null
    log "MySQL 8.0 部署完成 (root/gs 密码 ${pass})"
}

# ---------- ODBC 驱动 ----------
fed_install_odbc() {
    log "安装 ODBC (unixODBC + mariadb-connector-odbc)..."
    local d="$TLBB_OFFLINE_DIR/rpm-packages/fedora/odbc"
    if ls "$d"/*.rpm >/dev/null 2>&1; then
        dnf install -y --nogpgcheck "$d"/*.rpm >/dev/null 2>&1 || rpm -ivh --nodeps "$d"/*.rpm >/dev/null 2>&1
    else
        dnf install -y unixODBC mariadb-connector-odbc >/dev/null 2>&1 || true
    fi
    # DSN 配置 (对齐 gstlenv odbc.ini: tlbbdb)
    cat > /etc/odbc.ini <<ODBC
[tlbbdb]
Driver=$(ls /usr/lib64/libmaodbc.so /usr/lib64/libmyodbc*.so /usr/lib/libmaodbc.so 2>/dev/null | head -1)
Server=127.0.0.1
Port=${TL_MYSQL_PORT:-3306}
Database=tlbbdb
User=root
Password=${TLBB_DB_PASS:-123456}
ODBC
    [ -f /etc/odbcinst.ini ] || cat > /etc/odbcinst.ini <<ODBCI
[MySQL ODBC]
Driver=$(ls /usr/lib64/libmaodbc.so /usr/lib64/libmyodbc*.so /usr/lib/libmaodbc.so 2>/dev/null | head -1)
ODBCI
    log "ODBC DSN tlbbdb 已配置"
}

# ---------- Redis ----------
fed_install_redis() {
    log "安装 Redis (Fedora archive 6.x)..."
    local d="$TLBB_OFFLINE_DIR/rpm-packages/fedora/redis"
    if ls "$d"/*.rpm >/dev/null 2>&1; then
        dnf install -y --nogpgcheck "$d"/*.rpm >/dev/null 2>&1 || rpm -ivh --nodeps "$d"/*.rpm >/dev/null 2>&1
    else
        dnf install -y redis >/dev/null 2>&1 || true
    fi
    # 密码对齐 gstlenv (gsgameshare.com)
    sed -i 's/^# *requirepass.*/requirepass gsgameshare.com/; s/^requirepass.*/requirepass gsgameshare.com/' /etc/redis/redis.conf 2>/dev/null || true
    systemctl enable redis >/dev/null 2>&1
    systemctl restart redis >/dev/null 2>&1
    redis-cli -a gsgameshare.com ping >/dev/null 2>&1 && log "Redis 已启动 (密码 gsgameshare.com)" || warn "Redis 未响应 (可稍后手动启动)"
}

# ---------- 主流程 ----------
fed_install() {
    fed_config_source
    fed_install_compat
    fed_install_db
    fed_install_odbc
    fed_install_redis
    fed_verify
}

# ---------- 验证 (供 verify_offline.sh 复用: 4 项) ----------
fed_verify() {
    log "========== Fedora 环境验证 =========="
    local ok=0
    mysql -uroot -p"${TLBB_DB_PASS:-123456}" -e "SELECT 1" >/dev/null 2>&1 && \
        { log "[PASS] MySQL 运行中 ($(mysql -uroot -p"${TLBB_DB_PASS:-123456}" -N -e 'SELECT VERSION()' 2>/dev/null))"; ok=$((ok+1)); } || \
        warn "[FAIL] MySQL 未运行"
    isql -v tlbbdb -e "SELECT 1" >/dev/null 2>&1 && { log "[PASS] ODBC DSN tlbbdb 连通"; ok=$((ok+1)); } || warn "[FAIL] ODBC 未连通"
    redis-cli -a gsgameshare.com ping >/dev/null 2>&1 && { log "[PASS] Redis PONG"; ok=$((ok+1)); } || warn "[FAIL] Redis 未响应"
    log "Fedora 验证: $ok/3 通过"
}
