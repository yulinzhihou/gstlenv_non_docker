#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgameshare.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-04
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 校验并部署服务端压缩包, 默认目标为 /tlgame/tlbb。

untar_error() {
    printf '%s\n' "${CRED:-}解压失败: $*${CEND:-}" >&2
    printf '%s\n' "${GSISSUE:-问题反馈: https://gitee.com/yulinzhihou/gstlenv_non_docker/issues}" >&2
}

untar_deploy() (
    local archive="$1" target="${2%/}" backup_dir="$3"
    local parent name stage="" candidate="" dir entry kind tag backup="" archived extras
    local committed=0 roots=()
    [ -f "$archive" ] || { untar_error "未找到压缩包: $archive"; return 1; }
    case "$archive" in
        *.tar.gz|*.tgz) kind=tar;;
        *.zip) kind=zip; command -v unzip >/dev/null 2>&1 || { untar_error "缺少 unzip, 请先安装"; return 1; };;
        *) untar_error "仅支持 .tar.gz/.tgz/.zip 压缩包"; return 1;;
    esac
    archive="$(cd -P -- "$(dirname -- "$archive")" && pwd)/$(basename -- "$archive")"
    case "$target" in
        /*) :;;
        *) untar_error "TLBB_PATH 必须是非根目录的绝对路径: $target"; return 1;;
    esac
    name="${target##*/}"
    case "$name" in ''|.|..) untar_error "拒绝使用不安全的部署目录: $target"; return 1;; esac
    mkdir -p -- "$(dirname -- "$target")" || return 1
    parent=$(cd -P -- "$(dirname -- "$target")" && pwd) || return 1
    target="$parent/$name"
    case "$target" in
        /root|/usr|/etc|/var|/home|/tmp|/opt|/tlgame) untar_error "拒绝替换系统或数据根目录: $target"; return 1;;
    esac
    if [ -L "$target" ] || { [ -e "$target" ] && [ ! -d "$target" ]; }; then
        untar_error "目标必须是普通目录, 不能是文件或符号链接: $target"; return 1
    fi
    case "$archive" in "$target"/*) untar_error "压缩包不能放在将被替换的目标目录内"; return 1;; esac
    stage=$(mktemp -d "$parent/.untar.XXXXXX") || return 1
    # Restore the previous tree if the final move fails or is interrupted.
    untar_cleanup() {
        local rc=$?
        trap - EXIT
        if [ "$committed" = 0 ] && [ -d "$stage/previous" ]; then
            if [ -e "$target" ] || [ -L "$target" ] || ! mv -T -- "$stage/previous" "$target"; then
                untar_error "自动恢复未完成, 旧端保留在 $stage/previous, 请勿删除"
                return 1
            fi
        fi
        rm -rf -- "$stage"
        return "$rc"
    }
    trap untar_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir "$stage/content" || return 1
    printf '源压缩包: %s\n目标目录: %s\n' "$archive" "$target"
    if [ "$kind" = tar ]; then
        tar -tzf "$archive" > "$stage/members" || { untar_error "无法读取 tar.gz, 原包及旧端未改动"; return 1; }
    else
        unzip -Z -1 "$archive" > "$stage/members" || { untar_error "无法读取 zip, 原包及旧端未改动"; return 1; }
    fi
    while IFS= read -r entry || [ -n "$entry" ]; do
        entry="${entry//\\//}"
        case "$entry" in
            /*|[a-zA-Z]:*|../*|*/../*|*/..|..)
                untar_error "压缩包含不安全的路径: $entry"; return 1;;
        esac
    done < "$stage/members"
    if [ "$kind" = tar ]; then
        tar -xzf "$archive" --no-same-owner --no-same-permissions -C "$stage/content" || {
            untar_error "tar.gz 解压失败, 原包及旧端未改动"; return 1;
        }
    else
        unzip -q "$archive" -d "$stage/content" || { untar_error "zip 解压失败, 原包及旧端未改动"; return 1; }
    fi
    find "$stage/content" -type d -name Server -print0 > "$stage/servers" || return 1
    while IFS= read -r -d '' dir; do
        [ -d "$dir/Config" ] && [ ! -L "$dir/Config" ] || continue
        roots+=("${dir%/Server}")
    done < "$stage/servers"
    if [ "${#roots[@]}" != 1 ]; then
        untar_error "包内需有且仅有一套 Server/Config, 实际找到 ${#roots[@]} 套; 原包及旧端未改动"
        return 1
    fi
    candidate="${roots[0]}"
    for name in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
        if [ ! -f "$candidate/Server/Config/$name" ] || [ -L "$candidate/Server/Config/$name" ]; then
            untar_error "服务端缺少普通配置文件 Server/Config/$name, 原包及旧端未改动"; return 1
        fi
    done
    name="${target##*/}"
    tag="$(date +%Y%m%d%H%M%S)-${stage##*.}"
    if [ -d "$target" ]; then
        mkdir -p -- "$backup_dir" || { untar_error "无法创建备份目录: $backup_dir"; return 1; }
        backup_dir=$(cd -P -- "$backup_dir" && pwd) || return 1
        case "$backup_dir/" in "$target/"*) untar_error "备份目录不能位于被替换的服务端内"; return 1;; esac
        backup="$backup_dir/tlbb-before-untar-$tag.tar.gz"
        (umask 077; tar -czf "$backup.partial" -C "$parent" -- "$name") || {
            rm -f -- "$backup.partial"
            untar_error "旧端备份失败, 不替换旧端: $backup"; return 1;
        }
        mv -- "$backup.partial" "$backup" || { untar_error "无法保存旧端备份"; return 1; }
        printf '旧端备份: %s\n' "$backup"
        mv -T -- "$target" "$stage/previous" || { untar_error "无法移走旧端, 部署中止"; return 1; }
    fi
    mv -T -- "$candidate" "$target" || { untar_error "无法部署新端, 尝试恢复旧端"; return 1; }
    committed=1
    # Keep archive siblings (for example billing/) instead of silently discarding them.
    if [ -d "$stage/content" ] && [ -n "$(find "$stage/content" \( -type f -o -type l \) -print -quit)" ]; then
        extras="$parent/$name.archive-extra-$tag"
        mv -T -- "$stage/content" "$extras" || { untar_error "服务端已部署, 附属文件仍在 $stage/content"; trap - EXIT; return 1; }
        printf '包内其他文件已保留: %s\n' "$extras"
    fi
    archived="$(dirname -- "$archive")/$tag-$(basename -- "$archive")"
    if mv -- "$archive" "$archived"; then
        printf '原压缩包已保留为: %s\n' "$archived"
    else
        printf '警告: 服务端已部署, 原压缩包未能重命名, 仍在 %s\n' "$archive" >&2
    fi
    printf '%s\n' "${CSUCCESS:-}服务端解压并校验成功！${CEND:-}"
    printf '服务端目录: %s\n配置目录: %s/Server/Config\n下一步: setini\n' "$target" "$target"
)

untar_main() {
    { export LANG=C.UTF-8 LC_ALL=C.UTF-8; } 2>/dev/null
    [ "$(id -u)" = 0 ] || { untar_error "请使用 root 用户执行"; return 1; }
    if [ -f /root/.gs/.env ]; then
        source /root/.gs/.env || { untar_error "读取 /root/.gs/.env 失败, 不执行解压"; return 1; }
    fi
    [ -f /usr/local/bin/color ] && source /usr/local/bin/color
    local archive="${1:-}"
    [ "$#" -le 1 ] || { untar_error "用法: untar [压缩包路径]"; return 1; }
    if [ -z "$archive" ]; then
        if [ -f /root/tlbb.tar.gz ]; then archive=/root/tlbb.tar.gz
        elif [ -f /root/tlbb.zip ]; then archive=/root/tlbb.zip
        else untar_error "请上传 /root/tlbb.tar.gz 或 /root/tlbb.zip, 也可执行 untar /绝对路径/压缩包"; return 1
        fi
    fi
    [ -f "$archive" ] || { untar_error "未找到压缩包: $archive"; return 1; }
    if [ "${IS_DLQ:-0}" = 0 ]; then
        local helper loaded=0
        for helper in "$(dirname -- "${BASH_SOURCE[0]}")/billing-env.sh" /usr/local/bin/billing-env "${GS_PROJECT:-/root/.tlgame}/cmd/billing-env.sh"; do
            [ -f "$helper" ] || continue
            source "$helper" || return 1
            loaded=1; break
        done
        [ "$loaded" = 1 ] || { untar_error "缺少 Billing 部署组件, 请执行 upcmd 更新命令"; return 1; }
        billing_prepare "${GS_PROJECT:-/root/.tlgame}" "${TLBB_HOME:-/tlgame}/billing" \
            /home/billing /root/billing.tar.gz "${BACKUP_DIR:-/tlgame/backup}" || return 1
    else
        printf 'W机验证模式: 不部署或启动本机 Billing。\n'
    fi
    untar_deploy "$archive" "${TLBB_PATH:-${TLBB_HOME:-/tlgame}/tlbb}" "${BACKUP_DIR:-/root}" || return 1
    printf '%s\n' "${CSUCCESS:-}服务端文件已经解压成功！接下来执行【setini】写入配置文件；如需在线GM, 执行【upgm】配置, 最后执行【runtlbb】开服。${CEND:-}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    untar_main "$@"
fi
