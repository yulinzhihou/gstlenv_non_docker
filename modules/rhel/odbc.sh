#!/usr/bin/env bash

odbc_elf_bits() {
    [ -f "$1" ] || return 1
    [ "$(od -An -N4 -tx1 "$1" | tr -d ' \n')" = 7f454c46 ] || return 1
    case "$(od -An -j4 -N1 -tu1 "$1" | tr -d ' ')" in
        1) echo 32;;
        2) echo 64;;
        *) return 1;;
    esac
}

rhel_odbc_bits() {
    case "${TLBB_ODBC_BITS:-auto}" in
        32|64) echo "$TLBB_ODBC_BITS"; return 0;;
        auto) :;;
        *) err "TLBB_ODBC_BITS 只支持 auto|32|64" >&2; return 1;;
    esac
    local file bits
    for file in "${TLBB_PATH:-/tlgame/tlbb}"/Server/{Server,World,Login,ShareMem}; do
        bits=$(odbc_elf_bits "$file") || continue
        echo "$bits"; return 0
    done
    case "$SYS_BRANCH" in el5|el6|el7) echo 32;; *) getconf LONG_BIT;; esac
}

rhel_find_odbc_driver() {
    local bits="${1:-${TLBB_ODBC_BITS:-64}}" path deps
    local paths=()
    if [ "$bits" = 32 ]; then
        paths=(/usr/lib/libmyodbc3.so /usr/lib/libmaodbc.so /usr/lib/libmyodbc8w.so)
    else
        paths=(/usr/lib64/libmaodbc.so /usr/lib64/libmyodbc8w.so /usr/lib64/libmyodbc9w.so /usr/lib64/libmyodbc.so /usr/lib64/libmyodbc5w.so)
    fi
    for path in "${paths[@]}"; do
        [ "$(odbc_elf_bits "$path")" = "$bits" ] || continue
        deps=$(ldd "$path" 2>&1) || continue
        [[ "$deps" != *'not found'* ]] || continue
        printf '%s\n' "$path"; return 0
    done
    return 1
}

rhel_install_modern_odbc() {
    local bits mgr rpmfile arch dir native files=()
    bits=$(rhel_odbc_bits) || return 1
    if [ "$bits:$SYS_BRANCH" = 32:el10 ]; then
        err "检测到 32 位服务端, 但 EL10 不提供 i686 运行环境; 64 位驱动不能被 32 位进程加载。请使用 64 位服务端或 EL9。" >&2
        return 1
    fi
    TLBB_ODBC_BITS="$bits"
    log "ODBC 自动适配: ${SYS_BRANCH}/$(uname -m), 选择 ${bits} 位游戏驱动及本机 unixODBC 管理器"
    mgr=$(rhel_pkgmgr)
    native=$(uname -m)
    if [ "${TLBB_OFFLINE_MODE:-0}" = 1 ]; then
        dir="$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH"
        while IFS= read -r rpmfile; do
            arch=$(rpm -qp --qf '%{ARCH}' "$rpmfile" 2>/dev/null) || continue
            [ "$arch" = "$native" ] || [ "$arch" = noarch ] || continue
            files+=("$rpmfile")
        done < <(find "$dir/odbc" -maxdepth 1 -name '*.rpm' 2>/dev/null)
        if [ "${#files[@]}" -gt 0 ]; then
            "$mgr" --disablerepo='*' install -y "${files[@]}" >>"${TLBB_PKG_LOG:-/var/log/tlbb-packages.log}" 2>&1 || return 1
        fi
        if ! command -v isql >/dev/null 2>&1 || ! rhel_find_odbc_driver 64 >/dev/null; then
            rhel_config_repo force || return 1
            rhel_pkg_install unixODBC mariadb-connector-odbc || return 1
        fi
    else
        rhel_pkg_install unixODBC || return 1
        if ! rhel_find_odbc_driver 64 >/dev/null; then
            rhel_pkg_install mariadb-connector-odbc || rhel_pkg_install mysql-connector-odbc || return 1
        fi
    fi
    if [ "$bits" = 32 ]; then
        local driver
        driver=$(off_get el8_el9_el10/libmyodbc3-32bit libmyodbc3-3.51.27.so) || return 1
        rhel_pkg_install unixODBC.i686 || return 1
        [ "$(odbc_elf_bits "$driver")" = 32 ] || return 1
        cp -f "$driver" /usr/lib/libmyodbc3.so || return 1
        [ ! -f /usr/lib/libodbcinst.so.2 ] || ln -sf libodbcinst.so.2 /usr/lib/libodbcinst.so.1
        [ ! -f /usr/lib/libodbc.so.2 ] || ln -sf libodbc.so.2 /usr/lib/libodbc.so.1
    else
        log "已选择本机 64 位 ODBC, 不尝试安装无关的 unixODBC.i686"
    fi
    TLBB_ODBC_DRIVER=$(rhel_find_odbc_driver "$bits") || {
        err "${bits} 位 ODBC 驱动不存在或依赖不完整, 不生成无效 DSN" >&2
        return 1
    }
    log "ODBC 驱动已验证: $TLBB_ODBC_DRIVER"
}
