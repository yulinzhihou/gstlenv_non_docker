#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
source "$ROOT/modules/common.sh"
source "$ROOT/modules/rhel/install.sh"
PKG_ROOT="$ROOT"
TLBB_BOOTSTRAP_PASSWORD_FILE="$WORK/bootstrap.password"
TLBB_SQL_STATE_DIR="$WORK/import-state"
TLBB_MYSQL_VERSION=84
TLBB_DB_LAYOUT=3
TLBB_DB_PASS=123456
TLBB_MYSQL_USER=gs
TLBB_MYSQL_PASSWORD=123456
log() { :; }
warn() { :; }
err() { :; }
assert_equal() {
    if [ "$1" != "$2" ]; then
        printf 'FAIL: %s (actual=%s expected=%s)\n' "$3" "$1" "$2" >&2
        exit 1
    fi
}

assert_equal "$(rhel_main_database)" tlbbdb_main '8.4 three databases'
TLBB_DB_LAYOUT=2
assert_equal "$(rhel_main_database)" tlbbdb '8.4 two databases'
TLBB_DB_LAYOUT=3
TLBB_MYSQL_VERSION=57
assert_equal "$(rhel_main_database)" tlbbdb '5.7 always two databases'
TLBB_MYSQL_VERSION=84
printf '  create database if not exists `tlbbdb` DEFAULT CHARACTER SET utf8mb4;\nUSE `tlbbdb`;\nUSE tlbbdb;\nUSE `tlbbdb_10`;\nINSERT INTO x VALUES ("tlbbdb");\n' > "$WORK/input.sql"
rhel_rewrite_main_sql "$WORK/input.sql" > "$WORK/output.sql"
assert_equal "$(grep -c tlbbdb_main "$WORK/output.sql")" 3 'quoted/unquoted directives rewritten'
grep -q 'USE `tlbbdb_10`' "$WORK/output.sql"
grep -q 'VALUES ("tlbbdb")' "$WORK/output.sql"
assert_equal "$(rhel_sql_quote "a'b\\c")" "a''b\\\\c" 'SQL password escaping'
printf 'PASS: layout, SQL directives, password escaping\n'

(
    # Model credential transitions on disk because pipelines run in subshells.
    rhel_mysql() {
        local password="$1"; shift
        local state sql=""
        state=$(<"$WORK/state")
        if [[ " $* " == *" SELECT 1; "* ]]; then
            [ "$password" = "$state" ] && [ "$state" != 'expired' ]
            return
        fi
        sql=$(cat)
        printf '%s\n' "$sql" >> "$WORK/sql.log"
        [[ "$sql" != *'2>/dev/null'* ]] || return 1
        if [ "$password" = 'Temporary9!' ] && [ "$state" = expired ]; then
            [[ " $* " == *' --connect-expired-password '* ]] || return 1
        else
            [ "$password" = "$state" ] || return 1
        fi
        [[ "$sql" != UNINSTALL* ]] || return 1
        if [[ "$sql" == ALTER* || "$sql" == SET* ]]; then
            printf '%s\n' "$sql" | sed -n "s/.* BY '\([^']*\)';/\1/p" > "$WORK/state"
        fi
    }
    journalctl() { printf 'temporary password for root@localhost: Temporary9!\n'; }
    printf 'expired\n' > "$WORK/state"
    rhel_bootstrap_password
    assert_equal "$(<"$WORK/state")" 123456 'temporary to strong to target'
    [ ! -f "$TLBB_BOOTSTRAP_PASSWORD_FILE" ]
    printf 'Gstest@123456\n' > "$WORK/state"
    rhel_bootstrap_password
    assert_equal "$(<"$WORK/state")" 123456 'recover previous installer intermediate password'
    printf 'Saved9!password\n' > "$WORK/state"
    printf 'Saved9!password\n' > "$TLBB_BOOTSTRAP_PASSWORD_FILE"
    rhel_bootstrap_password
    assert_equal "$(<"$WORK/state")" 123456 'resume interrupted bootstrap'
    rhel_bootstrap_password
    assert_equal "$(<"$WORK/state")" 123456 'rerun with configured password'
    printf '\n' > "$WORK/state"
    rhel_bootstrap_password
    assert_equal "$(<"$WORK/state")" 123456 'empty password does not prompt'
    journalctl() { :; }
    printf 'unknown\n' > "$WORK/state"
    if rhel_bootstrap_password; then
        echo 'FAIL: unknown password must fail' >&2; exit 1
    fi
    assert_equal "$(<"$WORK/state")" unknown 'unknown credentials preserve data'
)
printf 'PASS: expired, interrupted, legacy intermediate, empty, rerun, unknown passwords\n'

(
    rhel_mysql() { shift; cat >> "$WORK/accounts.sql"; }
    mysql() { printf '%s\n' "$*" >> "$WORK/connections"; }
    rhel_create_databases
    grep -q "ALTER USER 'gs'@'localhost'" "$WORK/accounts.sql"
    grep -q "ALTER USER 'gs'@'%'" "$WORK/accounts.sql"
    grep -q "ALTER USER 'root'@'%'" "$WORK/accounts.sql"
    grep -q 'CREATE DATABASE IF NOT EXISTS `tlbbdb_main`' "$WORK/accounts.sql"
    grep -q 'CREATE DATABASE IF NOT EXISTS tlbbdb_10' "$WORK/accounts.sql"
    assert_equal "$(grep -c -- '--protocol=tcp' "$WORK/connections")" 2 'root and game TCP probes'
    assert_equal "$TLBB_DB_READY" 1 'database readiness only after successful checks'
)
printf 'PASS: existing account updates, database creation, authenticated TCP checks\n'

(
    TLBB_OFFLINE_DIR="$WORK/no-offline"
    rhel_import_one() { printf '%s %s\n' "$1" "$2" >> "$WORK/imports"; }
    rhel_import_databases
    assert_equal "$(wc -l < "$WORK/imports" | tr -d ' ')" 3 'online source includes all three SQL files'
    grep -q '/sql/mysql80/tlbbdb_10.sql' "$WORK/imports"
)
(
    rhel_mysql() { echo 12; }
    rhel_import_one tlbbdb_main "$WORK/nonexistent.sql" utf8mb4
)
(
    rhel_mysql() { return 1; }
    if rhel_import_one tlbbdb_main "$WORK/input.sql" utf8mb4; then
        echo 'FAIL: query failure must not look like empty database' >&2; exit 1
    fi
)
(
    rhel_mysql() {
        shift
        if [[ " $* " == *information_schema* ]]; then echo 0; else cat >/dev/null; return 1; fi
    }
    if rhel_import_one tlbbdb_main "$WORK/input.sql" utf8mb4; then
        echo 'FAIL: import pipeline must propagate mysql error' >&2; exit 1
    fi
    [ -f "$TLBB_SQL_STATE_DIR/tlbbdb_main.pending" ]
    rhel_mysql() { echo 1; }
    if rhel_import_one tlbbdb_main "$WORK/input.sql" utf8mb4; then
        echo 'FAIL: partial import must not be reported as a complete database' >&2; exit 1
    fi
)
printf 'PASS: bundled SQL, preserve populated database, query/import failure propagation\n'

(
    TLBB_OPT_NGINX=1 TLBB_OPT_PHP=1 TLBB_OPT_REDIS=1
    rhel_install_nginx() { return 1; }
    rhel_install_php() { printf 'php\n' >> "$WORK/optional"; }
    rhel_install_redis() { printf 'redis\n' >> "$WORK/optional"; }
    rhel_install_optional
    assert_equal "$TLBB_OPTIONAL_FAILED" 1 'optional failure recorded'
    assert_equal "$(wc -l < "$WORK/optional" | tr -d ' ')" 2 'other components still attempted'
)
printf 'PASS: optional install failure aggregation\n'
echo 'All installer regression checks passed.'
