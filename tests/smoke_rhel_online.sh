#!/usr/bin/env bash
# Run only in a disposable CentOS Stream 9/10 container, with this repo at /work.
# Stream 9's packaged mysqld has cap_sys_nice=ep; use docker --cap-add=SYS_NICE.
set -eo pipefail
[ -f /.dockerenv ] && [ "${TLBB_TEST_ALLOW_INSTALL:-0}" = "1" ] || {
    echo 'This test installs packages. Use a disposable Docker container with TLBB_TEST_ALLOW_INSTALL=1.' >&2
    exit 1
}
cd /work
PKG_ROOT=/work
source modules/common.sh
source modules/detect.sh
source modules/rhel/install.sh
detect_system
expected_branch="${1:-el10}"
[ "$SYS_ID:$SYS_BRANCH" = "centos:$expected_branch" ] || exit 1
TLBB_NONINTERACTIVE=1
TLBB_OFFLINE_MODE=0
TLBB_OFFLINE_DIR=/work/offline-does-not-exist
case "$expected_branch" in
    el9) TLBB_MYSQL_VERSION=80;;
    el10) TLBB_MYSQL_VERSION=84;;
    *) exit 1;;
esac
TLBB_DB_LAYOUT=3
TLBB_DB_PASS=123456
TLBB_OPT_NGINX=1
TLBB_OPT_PHP=1
TLBB_OPT_REDIS=1

# Containers have no systemd PID 1. Run the same package binaries/configurations;
# unit enablement and SELinux still require a full VM/host test.
systemctl() {
    local action="$1" svc="${@: -1}"
    [ "$action" != list-unit-files ] || return 0
    if [ "$action" = enable ]; then
        [[ " $* " == *' --now '* ]] || return 0
    fi
    case "$svc" in
        mysqld)
            if [ ! -d /var/lib/mysql/mysql ]; then
                mysqld --initialize --user=mysql || return 1
            fi
            mysqladmin ping >/dev/null 2>&1 || mysqld --user=mysql --daemonize
            ;;
        nginx) nginx;;
        php-fpm) mkdir -p /run/php-fpm; php-fpm -D;;
        valkey)
            mkdir -p /run/valkey
            chown valkey:valkey /run/valkey
            runuser -u valkey -- valkey-server /etc/valkey/valkey.conf --daemonize yes
            ;;
        redis)
            mkdir -p /run/redis
            chown redis:redis /run/redis
            runuser -u redis -- redis-server /etc/redis/redis.conf --daemonize yes
            ;;
        *) return 1;;
    esac
}

rhel_config_repo
rhel_install_compat
rhel_install_db
if [ "$expected_branch" = el9 ]; then
    rpm -q mysql-server
    mysql --version | grep -q '8\.0\.'
fi
rhel_start_db
rhel_setup_db
for db in tlbbdb_main tlbbdb_10 web; do
    count=$(rhel_mysql "$TLBB_DB_PASS" -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db';")
    [ "$count" -gt 0 ] || exit 1
    printf 'PASS: %s has %s tables\n' "$db" "$count"
done
count=$(rhel_mysql "$TLBB_DB_PASS" -Nse "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='tlbbdb';")
[ "$count" = 0 ] || { echo 'Unexpected legacy database from failed rewrite'; exit 1; }
rhel_mysql "$TLBB_DB_PASS" -e 'CREATE TABLE tlbbdb_main.installer_preserve_probe (id INT); INSERT INTO tlbbdb_main.installer_preserve_probe VALUES (42);'
rhel_setup_db
[ "$(rhel_mysql "$TLBB_DB_PASS" -Nse 'SELECT id FROM tlbbdb_main.installer_preserve_probe;')" = 42 ]
echo 'PASS: rerun preserves populated databases'

# Exercise recovery from the exact intermediate password left by the old script.
rhel_set_root_password "$TLBB_DB_PASS" 'Gstest@123456'
rhel_setup_db
echo 'PASS: previous installer intermediate password recovered'

rhel_mysql "$TLBB_DB_PASS" -e 'CREATE DATABASE installer_failed_import;'
printf 'CREATE TABLE import_probe (id INT);\nINVALID SQL;\n' > /tmp/tlbb-invalid-import.sql
if rhel_import_one installer_failed_import /tmp/tlbb-invalid-import.sql utf8mb4; then
    echo 'FAIL: invalid SQL accepted'; exit 1
fi
if rhel_import_one installer_failed_import /tmp/tlbb-invalid-import.sql utf8mb4; then
    echo 'FAIL: partial import reported as complete'; exit 1
fi
echo 'PASS: partial import remains an explicit error on rerun'

TLBB_DB_LAYOUT=2
rhel_setup_db
[ "$(rhel_mysql "$TLBB_DB_PASS" -Nse 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema="tlbbdb";')" = 50 ]
TLBB_DB_LAYOUT=3
echo 'PASS: two-database layout imports its own main database'

# Escaping must survive both SQL execution and subsequent login.
TLBB_DB_PASS="Tmp9!quo'te\\slash"
rhel_set_root_password 123456 "$TLBB_DB_PASS"
rhel_bootstrap_password
rhel_create_databases
echo 'PASS: quotes and backslashes in root password'

rhel_install_optional
[ "${TLBB_OPTIONAL_FAILED:-0}" = 0 ] || exit 1
nginx -t
php -r 'exit(extension_loaded("mysqli") && extension_loaded("mbstring") ? 0 : 1);'
rcli=redis-cli
command -v valkey-cli >/dev/null 2>&1 && rcli=valkey-cli
REDISCLI_AUTH="$TLBB_REDIS_PASSWORD" "$rcli" ping | grep -qx PONG
echo 'PASS: nginx, PHP/FPM/MySQL extension, Redis/Valkey authenticated PING'
mysql --version
nginx -v
php -v | head -n 1
"$rcli" --version
printf 'CentOS Stream %s online smoke test passed.\n' "${expected_branch#el}"
