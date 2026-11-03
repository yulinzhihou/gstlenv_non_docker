#!/usr/bin/env bash
# Run against an image saved from a successful smoke_el9.sh/smoke_el10.sh container.
set -eo pipefail
[ -f /.dockerenv ] && [ "${TLBB_TEST_ALLOW_INSTALL:-0}" = 1 ] || exit 1
[ -f /root/.gs/.env ] || { echo 'Run the online smoke test first.' >&2; exit 1; }
source /work/install.sh
source /root/.gs/.env
detect_system
TLBB_NONINTERACTIVE=1
TLBB_OFFLINE_MODE=0
mysqld --user=mysql --daemonize

# Only the Redis restart needs a container replacement for systemd.
systemctl() {
    if [ "$1" != restart ]; then command systemctl "$@"; return $?; fi
    case "${@: -1}" in
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

# Reproduce an older completed installation without changing its game data.
rhel_set_root_password "$TLBB_DB_PASS" 123456
TLBB_DB_PASS=123456
TLBB_MYSQL_PASSWORD=123456
rhel_create_databases
TLBB_REDIS_PASSWORD=gsgameshare.com
rhel_install_redis
rcli=redis-cli
command -v valkey-cli >/dev/null 2>&1 && rcli=valkey-cli
REDISCLI_AUTH="$TLBB_REDIS_PASSWORD" "$rcli" shutdown nosave
printf '%s\n' 'TL_MYSQL_PASSWORD=123456' 'REDIS_PASSWORD=gsgameshare.com' \
    'LOGIN_PASSWORD=gsgameshare.com' 'PRIVATE_KEY=Gsgameshare.com2025' > /root/.gs/.env
unset TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY TLBB_DB_CURRENT_PASS TLBB_CREDENTIALS_READY
prepare_credentials
[ "$TLBB_DB_CURRENT_PASS" = 123456 ]
rhel_setup_db
[ "$(rhel_mysql "$TLBB_DB_PASS" -Nse 'SELECT id FROM tlbbdb_main.installer_preserve_probe;')" = 42 ]
if rhel_mysql 123456 -Nse 'SELECT 1;' >/dev/null 2>&1; then
    echo 'FAIL: legacy root password remains active'; exit 1
fi
TLBB_OPT_NGINX=0 TLBB_OPT_PHP=0 TLBB_OPT_REDIS=0
rhel_install_optional
[ "${TLBB_OPTIONAL_FAILED:-0}" = 0 ]
REDISCLI_AUTH="$TLBB_REDIS_PASSWORD" "$rcli" ping | grep -qx PONG
if REDISCLI_AUTH=gsgameshare.com "$rcli" ping 2>/dev/null | grep -qx PONG; then exit 1; fi
rhel_config_odbc
gen_env
[ ! -f /root/.gs/credentials.pending.env ]
(
    unset TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY TLBB_DB_CURRENT_PASS TLBB_CREDENTIALS_READY
    prepare_credentials
    source /root/.gs/.env
    [ "$TLBB_DB_PASS" = "$TL_MYSQL_PASSWORD" ]
    [ "$TLBB_REDIS_PASSWORD" = "$REDIS_PASSWORD" ]
    rhel_mysql "$TLBB_DB_PASS" -Nse 'SELECT 1;' >/dev/null
)
echo 'PASS: legacy weak credentials migrated, data preserved, old root/Redis passwords retired, rerun authenticates'

# Exercise the real application writers with generated secrets in a private fixture.
fixture=$(mktemp -d)
mkdir -p "$fixture/game/Server/Config" "$fixture/game/Script" "$fixture/project"
printf '[Mother]\nIP=old\n[World]\nIP=old\n' > "$fixture/game/Server/Config/ServerInfo.ini"
for file in LoginInfo ShareMemInfo; do
    printf '[System]\nDBIP=old\nDBPort=0\nDBName=old\nDBUser=old\nDBPassword=old\n' > "$fixture/game/Server/Config/$file.ini"
done
printf 'GMDATA_ISOPEN_GMTOOLS=0\nGMDATA_PRIVATE_KEY="old"\n' > "$fixture/game/Script/ScriptGlobal.lua"
printf 'GS_PROJECT=%q\nTLBB_PATH=%q\n' "$fixture/project" "$fixture/game" >> /root/.gs/.env
bash /work/cmd/setini.sh
bash /work/cmd/upgm.sh
source /root/.gs/.env
for file in LoginInfo ShareMemInfo; do
    tr -d '\r' < "$fixture/game/Server/Config/$file.ini" | grep -Fqx "DBPassword=$TLBB_MYSQL_PASSWORD"
    tr -d '\r' < "$fixture/game/Server/Config/$file.ini" | grep -qx 'DBUser=gs'
done
for dsn in tlbbdb tlbbdb_main tlbbdb_10 CHAR_DBTABASE; do
    printf 'SELECT 1;\n' | isql -b "$dsn" >/dev/null
done
grep -Fq "db_password: $TLBB_MYSQL_PASSWORD" /home/billing/config.yaml
grep -Fqx "GMDATA_PRIVATE_KEY=\"$PRIVATE_KEY\"" "$fixture/game/Script/ScriptGlobal.lua"
php -l /tlgame/www/gm/DBConfig.php
php -r 'require "/tlgame/www/gm/DBConfig.php"; $db = new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME, $DB_PORT); exit($db->connect_errno ? 1 : 0);'
[ "$(stat -c %a /etc/odbc.ini)" = 600 ]
echo 'PASS: setini and GM preserve generated secrets, valid PHP and quoted Lua key, all game DSNs connect'
echo 'Runtime upgrade and application configuration smoke test passed.'
