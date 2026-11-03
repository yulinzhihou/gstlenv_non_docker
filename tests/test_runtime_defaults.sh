#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
source "$ROOT/modules/common.sh"
source "$ROOT/modules/rhel/install.sh"
log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
clear_credentials() {
    unset TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY TLBB_DB_CURRENT_PASS TLBB_CREDENTIALS_READY
}
check_password() {
    [ "${#1}" = 12 ]
    [[ "$1" == *[A-Z]* && "$1" == *[a-z]* && "$1" == *[0-9]* && "$1" == *[_+=.-]* ]]
}
for i in {1..50}; do check_password "$(random_password)"; done
clear_credentials
TLBB_STATE_DIR="$WORK/new"
prepare_credentials > "$WORK/log"
for var in TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY; do
    check_password "${!var}"
    ! grep -Fq -- "${!var}" "$WORK/log"
done
[ "$(stat -c %a "$TLBB_STATE_DIR/credentials.pending.env")" = 600 ]
before=$(cksum "$TLBB_STATE_DIR/credentials.pending.env")
clear_credentials
prepare_credentials >/dev/null
[ "$(cksum "$TLBB_STATE_DIR/credentials.pending.env")" = "$before" ]
echo 'PASS: 12-character mixed secrets, private persistence, interruption reuse, no log exposure'

clear_credentials
TLBB_STATE_DIR="$WORK/legacy"
mkdir -p "$TLBB_STATE_DIR"
printf '%s\n' 'TL_MYSQL_PASSWORD=123456' 'REDIS_PASSWORD=gsgameshare.com' 'LOGIN_PASSWORD=gsgameshare.com' 'PRIVATE_KEY=Gsgameshare.com2025' > "$TLBB_STATE_DIR/.env"
prepare_credentials >/dev/null
[ "$TLBB_DB_CURRENT_PASS" = 123456 ]
for var in TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY; do check_password "${!var}"; done
rm "$TLBB_STATE_DIR/credentials.pending.env"
printf 'TL_MYSQL_PASSWORD=%q\nTLBB_MYSQL_PASSWORD=%q\nREDIS_PASSWORD=%q\nLOGIN_PASSWORD=%q\nPRIVATE_KEY=%q\n' \
    "$TLBB_DB_PASS" "$TLBB_MYSQL_PASSWORD" "$TLBB_REDIS_PASSWORD" "$TLBB_GM_PASSWORD" "$TLBB_PRIVATE_KEY" > "$TLBB_STATE_DIR/.env"
original="$TLBB_DB_PASS"
clear_credentials
prepare_credentials >/dev/null
[ "$TLBB_DB_PASS" = "$original" ]
clear_credentials
TLBB_DB_PASS='Explicit9!override'
prepare_credentials >/dev/null
[ "$TLBB_DB_PASS" = 'Explicit9!override' ]
[ "$TLBB_DB_CURRENT_PASS" = "$original" ]
echo 'PASS: legacy weak defaults migrate, saved strong values persist, explicit overrides win'

clear_credentials
TLBB_STATE_DIR="$WORK/invalid"
mkdir -p "$TLBB_STATE_DIR"
printf 'return 9\n' > "$TLBB_STATE_DIR/.env"
if prepare_credentials; then echo 'FAIL: malformed saved config accepted'; exit 1; fi
[ ! -f "$TLBB_STATE_DIR/credentials.pending.env" ]
echo 'PASS: unreadable saved configuration fails closed'

(
    clear_credentials
    TLBB_STATE_DIR="$WORK/no-random"
    od() { return 1; }
    if prepare_credentials >/dev/null 2>&1; then echo 'FAIL: random source failure accepted'; exit 1; fi
    [ ! -f "$TLBB_STATE_DIR/credentials.pending.env" ]
)
echo 'PASS: random source failure does not save empty credentials'

(
    TLBB_OPT_NGINX=0 TLBB_OPT_PHP=0 TLBB_OPT_REDIS=0
    command() {
        if [ "$*" = '-v valkey-server' ]; then return 0; fi
        if [ "$*" = '-v redis-server' ]; then return 1; fi
        builtin command "$@"
    }
    rhel_install_redis() { echo synced > "$WORK/redis-synced"; }
    rhel_install_optional >/dev/null
    [ "$(<"$WORK/redis-synced")" = synced ]
)
echo 'PASS: installed Redis credentials synchronize even when optional installation is declined'

(
    systemctl() {
        case "$1" in
            list-unit-files) printf '%s\n' 'mysqld.service enabled disabled' 'mysql.service alias -' 'nginx.service disabled disabled' 'php-fpm.service disabled disabled' 'valkey.service disabled disabled' 'sshd.service enabled enabled';;
            enable) printf '%s\n' "$2" >> "$WORK/enabled";;
            is-enabled) echo enabled;;
            *) return 1;;
        esac
    }
    enable_installed_services >/dev/null
    [ "$(wc -l < "$WORK/enabled")" = 4 ]
    grep -qx php-fpm.service "$WORK/enabled"
    ! grep -q sshd "$WORK/enabled"
    systemctl() {
        case "$1" in
            list-unit-files) echo 'php-fpm.service disabled disabled';;
            enable) return 0;;
            is-enabled) echo disabled; return 1;;
        esac
    }
    if enable_installed_services >/dev/null 2>&1; then echo 'FAIL: disabled service accepted'; exit 1; fi
)
echo 'PASS: stack services enabled, aliases/unrelated services excluded, state failures propagate'

TLBB_PATH="$WORK/game"
SYS_BRANCH=el10
TLBB_ODBC_BITS=auto
[ "$(rhel_odbc_bits)" = 64 ]
(
    TLBB_OFFLINE_MODE=1
    rhel_pkg_install() { echo 'FAIL: EL10 must not install i686 packages' >&2; exit 1; }
    rhel_install_compat >/dev/null
)
mkdir -p "$TLBB_PATH/Server"
printf '\177ELF\001' > "$TLBB_PATH/Server/Server"
[ "$(rhel_odbc_bits)" = 32 ]
TLBB_OFFLINE_MODE=0
if rhel_install_modern_odbc >/dev/null 2>&1; then echo 'FAIL: 64-bit driver substituted for a 32-bit process'; exit 1; fi
printf '\177ELF\002' > "$TLBB_PATH/Server/Server"
[ "$(rhel_odbc_bits)" = 64 ]
TLBB_ODBC_BITS=invalid
if rhel_odbc_bits >/dev/null 2>&1; then exit 1; fi
(
    TLBB_ODBC_BITS=auto
    rhel_pkg_install() { printf '%s\n' "$*" >> "$WORK/odbc-packages"; }
    rhel_find_odbc_driver() { echo /usr/lib64/libmaodbc.so; }
    rhel_install_modern_odbc >/dev/null
    ! grep -q i686 "$WORK/odbc-packages"
    [ "$TLBB_ODBC_BITS" = 64 ]
    [ "$TLBB_ODBC_DRIVER" = /usr/lib64/libmaodbc.so ]
)
echo 'PASS: ELF/system architecture selection, no blind i686 install, incompatible binaries rejected'
echo 'All runtime default checks passed.'
