#!/usr/bin/env bash

random_password() {
    local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+=.-'
    local result byte bytes limit=$((256 / 67 * 67))
    while :; do
        result=""
        while [ "${#result}" -lt 12 ]; do
            bytes=$(od -An -N48 -tu1 /dev/urandom) || return 1
            [ -n "$bytes" ] || return 1
            for byte in $bytes; do
                [ "$byte" -lt "$limit" ] || continue
                result="${result}${alphabet:byte%67:1}"
                [ "${#result}" -lt 12 ] || break
            done
        done
        [[ "$result" == *[A-Z]* && "$result" == *[a-z]* && "$result" == *[0-9]* && "$result" == *[_+=.-]* ]] || continue
        printf '%s\n' "$result"
        return 0
    done
}

# Pending targets survive interrupted installation; the runtime .env stays active
# until services have accepted these credentials.
saved_credentials() (
    local dir="${TLBB_STATE_DIR:-/root/.gs}" var
    if [ -f "$dir/.env" ]; then
        source "$dir/.env" || return 1
        TLBB_DB_PASS="${TL_MYSQL_PASSWORD:-${TLBB_DB_PASS:-}}"
        TLBB_REDIS_PASSWORD="${REDIS_PASSWORD:-${TLBB_REDIS_PASSWORD:-}}"
        TLBB_GM_PASSWORD="${LOGIN_PASSWORD:-${TLBB_GM_PASSWORD:-}}"
        TLBB_PRIVATE_KEY="${PRIVATE_KEY:-${TLBB_PRIVATE_KEY:-}}"
        TLBB_DB_CURRENT_PASS="${TLBB_DB_PASS:-}"
    fi
    [ ! -f "$dir/credentials.pending.env" ] || source "$dir/credentials.pending.env" || return 1
    for var in TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY TLBB_DB_CURRENT_PASS; do
        printf '%s\0%s\0' "$var" "${!var:-}"
    done
)

prepare_credentials() {
    [ "${TLBB_CREDENTIALS_READY:-0}" != 1 ] || return 0
    local dir="${TLBB_STATE_DIR:-/root/.gs}" var value temp
    local pending=0
    [ ! -f "$dir/credentials.pending.env" ] || pending=1
    (umask 077; mkdir -p "$dir"; chmod 700 "$dir") || return 1
    temp=$(mktemp "$dir/credentials.XXXXXX") || return 1
    saved_credentials > "$temp" || { rm -f "$temp"; return 1; }
    while IFS= read -r -d '' var && IFS= read -r -d '' value; do
        [ -z "${!var:-}" ] || continue
        # Only migrate old built-in defaults, never replace an explicit override.
        if [ "$pending" = 0 ]; then
            case "$var:$value" in
                TLBB_DB_PASS:123456|TLBB_MYSQL_PASSWORD:123456|TLBB_REDIS_PASSWORD:gsgameshare.com|TLBB_GM_PASSWORD:gsgameshare.com|TLBB_PRIVATE_KEY:Gsgameshare.com2025) value="";;
            esac
        fi
        printf -v "$var" '%s' "$value"
    done < "$temp"
    for var in TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY; do
        if [ -z "${!var:-}" ]; then
            value=$(random_password) || { rm -f "$temp"; return 1; }
            printf -v "$var" '%s' "$value"
        fi
    done
    for var in TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY TLBB_DB_CURRENT_PASS; do
        printf '%s=%q\n' "$var" "${!var:-}" || { rm -f "$temp"; return 1; }
    done > "$temp"
    chmod 600 "$temp" && mv -f "$temp" "$dir/credentials.pending.env" || return 1
    TLBB_CREDENTIALS_READY=1
    export TLBB_DB_PASS TLBB_MYSQL_PASSWORD TLBB_REDIS_PASSWORD TLBB_GM_PASSWORD TLBB_PRIVATE_KEY
    log "服务凭据已准备并私密保存 (默认使用独立的 12 位随机密码, 不输出到安装日志)"
}
