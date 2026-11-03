#!/usr/bin/env bash

# Keep password-bearing statements out of command arguments and package logs.
rhel_mysql() {
    local password="$1"; shift
    MYSQL_PWD="$password" mysql --no-defaults --protocol=socket -uroot "$@"
}

rhel_sql_quote() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\'/\'\'}
    printf '%s' "$value"
}

rhel_set_root_password() {
    local current="$1" password="$2" mver
    local options=()
    mver=$(select_mysql_version)
    password=$(rhel_sql_quote "$password")
    [ "$mver" = "51" ] || options=(--connect-expired-password)
    if [ "$mver" = "51" ]; then
        printf "UPDATE mysql.user SET Password=PASSWORD('%s') WHERE User='root'; FLUSH PRIVILEGES;\n" "$password"
    else
        printf "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '%s';\n" "$password"
    fi | rhel_mysql "$current" "${options[@]}"
}

rhel_disable_password_policy() {
    local password="$1" mver
    mver=$(select_mysql_version)
    # A missing component/plugin is expected. Never combine these with ALTER USER.
    case "$mver" in
        80|84) printf "UNINSTALL COMPONENT 'file://component_validate_password';\n" | rhel_mysql "$password" >/dev/null 2>&1 || true;;
        57) printf "UNINSTALL PLUGIN validate_password;\n" | rhel_mysql "$password" >/dev/null 2>&1 || true;;
    esac
}

rhel_bootstrap_password() {
    local current="" found=0 candidate logf tmp_pw="" strong
    local recovery="${TLBB_BOOTSTRAP_PASSWORD_FILE:-/root/.gs/mysql-bootstrap.password}"
    # Older installers could stop after setting Gstest@<target>, before the final ALTER.
    local saved=""
    [ -r "$recovery" ] && IFS= read -r saved < "$recovery"
    for candidate in "$TLBB_DB_PASS" "${TLBB_DB_CURRENT_PASS:-}" "$saved" "Gstest@${TLBB_DB_PASS}" ""; do
        if rhel_mysql "$candidate" -Nse 'SELECT 1;' </dev/null >/dev/null 2>&1; then
            current="$candidate"; found=1; break
        fi
    done
    if [ "$found" = "0" ]; then
        for logf in /var/log/mysqld.log /var/log/mysql/mysqld.log /var/log/mysql/error.log; do
            [ -f "$logf" ] || continue
            tmp_pw=$(grep -a 'temporary password' "$logf" | tail -1 | sed 's/.*: //')
            [ -n "$tmp_pw" ] && break
        done
        if [ -z "$tmp_pw" ]; then
            tmp_pw=$(journalctl -u mysqld --no-pager 2>/dev/null | grep -a 'temporary password' | tail -1 | sed 's/.*: //')
        fi
        if [ -z "$tmp_pw" ]; then
            err "无法认证 root; 保留现有数据库。已知旧密码可通过 TLBB_DB_CURRENT_PASS 指定。" >&2
            return 1
        fi
        strong="Gs9!$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
        # Save before ALTER, so an interrupted bootstrap can resume without bypassing grants.
        (umask 077; mkdir -p "$(dirname "$recovery")"; printf '%s\n' "$strong" > "$recovery"; chmod 600 "$recovery") || return 1
        log "检测到临时密码, 先解除过期状态, 再配置目标密码..."
        # Use the default plugin here: even an expired account must be able to reset itself.
        candidate=$(rhel_sql_quote "$strong")
        printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" "$candidate" | \
            rhel_mysql "$tmp_pw" --connect-expired-password >/dev/null || return 1
        current="$strong"
    fi
    rhel_disable_password_policy "$current"
    rhel_set_root_password "$current" "$TLBB_DB_PASS" >/dev/null || return 1
    rhel_mysql "$TLBB_DB_PASS" -Nse 'SELECT 1;' </dev/null >/dev/null || return 1
    rm -f "$recovery"
    log "MySQL root 本地密码认证验证通过"
}

rhel_main_database() {
    case "$(select_mysql_version):${TLBB_DB_LAYOUT:-3}" in
        80:3|84:3) echo tlbbdb_main;;
        *) echo tlbbdb;;
    esac
}

rhel_create_databases() {
    local mver main_db cs="utf8mb4" user pass rootpass host
    mver=$(select_mysql_version); main_db=$(rhel_main_database)
    [ "$mver" = "51" ] && cs="utf8"
    user=$(rhel_sql_quote "$TLBB_MYSQL_USER")
    pass=$(rhel_sql_quote "$TLBB_MYSQL_PASSWORD")
    rootpass=$(rhel_sql_quote "$TLBB_DB_PASS")
    log "配置 MySQL 账号并建库 (主库 ${main_db})..."
    # ALTER as well as CREATE is required on reruns: IF NOT EXISTS does not update passwords.
    {
        for host in localhost '%'; do
            if [ "$mver" = "51" ]; then
                printf "GRANT ALL PRIVILEGES ON *.* TO '%s'@'%s' IDENTIFIED BY '%s' WITH GRANT OPTION;\n" "$user" "$host" "$pass"
            else
                printf "CREATE USER IF NOT EXISTS '%s'@'%s' IDENTIFIED WITH mysql_native_password BY '%s';\n" "$user" "$host" "$pass"
                printf "ALTER USER '%s'@'%s' IDENTIFIED WITH mysql_native_password BY '%s';\n" "$user" "$host" "$pass"
                printf "GRANT ALL PRIVILEGES ON *.* TO '%s'@'%s' WITH GRANT OPTION;\n" "$user" "$host"
            fi
        done
        if [ "$mver" = "51" ]; then
            printf "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%%' IDENTIFIED BY '%s' WITH GRANT OPTION;\n" "$rootpass"
        else
            printf "CREATE USER IF NOT EXISTS 'root'@'%%' IDENTIFIED WITH mysql_native_password BY '%s';\n" "$rootpass"
            printf "ALTER USER 'root'@'%%' IDENTIFIED WITH mysql_native_password BY '%s';\n" "$rootpass"
            printf "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%%' WITH GRANT OPTION;\n"
        fi
        printf 'CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET %s;\n' "$main_db" "$cs"
        printf 'CREATE DATABASE IF NOT EXISTS web CHARACTER SET %s;\n' "$cs"
        [ "$main_db" != "tlbbdb_main" ] || printf 'CREATE DATABASE IF NOT EXISTS tlbbdb_10 CHARACTER SET utf8mb4;\n'
        printf 'FLUSH PRIVILEGES;\n'
    } | rhel_mysql "$TLBB_DB_PASS" || return 1
    # mysqladmin ping also succeeds on access-denied; exercise an authenticated query instead.
    MYSQL_PWD="$TLBB_DB_PASS" mysql --no-defaults --protocol=tcp -h127.0.0.1 \
        -P"${TLBB_MYSQL_PORT:-3306}" -uroot -Nse 'SELECT 1;' </dev/null >/dev/null || return 1
    MYSQL_PWD="$TLBB_MYSQL_PASSWORD" mysql --no-defaults --protocol=tcp -h127.0.0.1 \
        -P"${TLBB_MYSQL_PORT:-3306}" -u"$TLBB_MYSQL_USER" -Nse 'SELECT 1;' </dev/null >/dev/null || return 1
    TLBB_DB_READY=1
    log "MySQL root/游戏账号认证及建库通过 (Socket + TCP)"
}

rhel_rewrite_main_sql() {
    # Only rewrite database directives, not comments or inserted character data.
    sed -E \
        -e 's/^([[:space:]]*CREATE[[:space:]]+DATABASE[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?)(`?)tlbbdb(`?)([[:space:];])/\1\3tlbbdb_main\4\5/I' \
        -e 's/^([[:space:]]*USE[[:space:]]+)(`?)tlbbdb(`?)([[:space:];])/\1\2tlbbdb_main\3\4/I' "$1"
}

rhel_import_one() {
    local db="$1" file="$2" cs="$3" tables
    local state_dir="${TLBB_SQL_STATE_DIR:-/root/.gs/sql-import}"
    tables=$(rhel_mysql "$TLBB_DB_PASS" -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db';") || return 1
    if [ "${tables:-0}" -gt 0 ]; then
        if [ -f "$state_dir/$db.pending" ]; then
            err "${db} 上次导入未完成; 保留现有表, 请先备份并检查 SQL 错误, 不自动覆盖" >&2
            return 1
        fi
        log "${db} 已有 ${tables} 张表, 保留现有数据, 不重复导入"
        return 0
    fi
    [ -f "$file" ] || { err "缺少初始化 SQL: $file" >&2; return 1; }
    (umask 077; mkdir -p "$state_dir"; printf '%s\n' "$file" > "$state_dir/$db.pending") || return 1
    log "导入 ${db}: $file"
    if [ "$db" = "tlbbdb_main" ]; then
        (set -o pipefail; rhel_rewrite_main_sql "$file" | \
            rhel_mysql "$TLBB_DB_PASS" --default-character-set="$cs" "$db") || return 1
    else
        rhel_mysql "$TLBB_DB_PASS" --default-character-set="$cs" "$db" < "$file" || return 1
    fi
    rm -f "$state_dir/$db.pending"
    log "${db} 导入成功"
}

rhel_import_databases() {
    local version main_db dir sql_dir="" cs="utf8mb4"
    version=$(select_mysql_version); main_db=$(rhel_main_database)
    [ "$version" != "84" ] || version=80
    [ "$version" != "51" ] || cs="utf8"
    for dir in "${TLBB_SQL_DIR:-}" "$TLBB_OFFLINE_DIR/sql/mysql${version}" "${PKG_ROOT}/sql/mysql${version}"; do
        [ -n "$dir" ] && [ -f "$dir/tlbbdb.sql" ] && [ -f "$dir/web.sql" ] || continue
        sql_dir="$dir"; break
    done
    [ -n "$sql_dir" ] || { err "未找到 mysql${version} 初始 SQL, 可用 TLBB_SQL_DIR 指定目录" >&2; return 1; }
    rhel_import_one "$main_db" "$sql_dir/tlbbdb.sql" "$cs" || return 1
    rhel_import_one web "$sql_dir/web.sql" "$cs" || return 1
    [ "$main_db" != "tlbbdb_main" ] || rhel_import_one tlbbdb_10 "$sql_dir/tlbbdb_10.sql" "$cs" || return 1
    TLBB_SQL_READY=1
}
