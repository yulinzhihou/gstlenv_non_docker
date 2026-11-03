#!/usr/bin/env bash

enable_installed_services() {
    local unit state units failed=0 count=0 svc
    if command -v systemctl >/dev/null 2>&1; then
        units=$(systemctl list-unit-files --type=service --no-legend --no-pager) || return 1
        while read -r unit state; do
            case "$unit" in
                mysqld.service|mysql.service|mysql-generic.service|nginx.service|redis.service|redis-server.service|valkey.service|php-fpm.service|php[0-9]*-fpm.service|php[0-9]*.[0-9]*-fpm.service) :;;
                *) continue;;
            esac
            # Enable real units; aliases follow the target unit.
            [ "${state%% *}" != alias ] || continue
            count=$((count + 1))
            if systemctl enable "$unit" && [ "$(systemctl is-enabled "$unit")" = enabled ]; then
                log "开机自启已验证: $unit"
            else
                warn "开机自启设置失败: $unit" >&2
                failed=1
            fi
        done <<< "$units"
    else
        for svc in mysqld mysql mysql-generic nginx redis redis-server valkey php-fpm php[0-9]*-fpm; do
            [ -x "/etc/init.d/$svc" ] || continue
            count=$((count + 1))
            if command -v chkconfig >/dev/null 2>&1; then
                chkconfig "$svc" on || failed=1
            elif command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$svc" defaults && update-rc.d "$svc" enable || failed=1
            else
                failed=1
            fi
        done
    fi
    [ "$count" -gt 0 ] || { warn "未找到可启用的已安装环境服务" >&2; return 1; }
    [ "$failed" = 0 ]
}
