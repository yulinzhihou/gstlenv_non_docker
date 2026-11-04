#!/usr/bin/env bash
# Shared native Billing deployment. Sourcing this file never starts a service.

billing_error() {
    printf 'Billing 部署失败: %s\n' "$*" >&2
    printf '%s\n' '问题反馈: https://gitee.com/yulinzhihou/gstlenv_non_docker/issues' >&2
}

billing_arch() {
    case "$(uname -m)" in
        x86_64|amd64) printf '64:2:62\n';;
        i386|i486|i586|i686) printf '32:1:3\n';;
        aarch64|arm64) printf 'arm64:2:183\n';;
        armv7l|armv6l) printf 'arm:1:40\n';;
        *) billing_error "不支持的系统架构: $(uname -m)"; return 1;;
    esac
}

billing_check_elf() {
    local file="$1" arch="$2" class machine
    [ -f "$file" ] && [ "$(wc -c < "$file")" -ge 64 ] &&
        [ "$(od -An -N4 -tx1 "$file" | tr -d ' \n')" = 7f454c46 ] &&
        [ "$(od -An -j5 -N1 -tu1 "$file" | tr -d ' \n')" = 1 ] || {
            billing_error "不是有效的 Linux 小端 ELF 程序: $file"; return 1;
        }
    class=$(od -An -j4 -N1 -tu1 "$file" | tr -d ' \n')
    machine=$(od -An -j18 -N2 -tu1 "$file" | awk '{ print $1 + 256 * $2 }')
    [ "${arch#*:}" = "$class:$machine" ] || {
        billing_error "程序架构与当前系统不匹配 (需要 $arch, 实际 $class:$machine): $file"; return 1;
    }
}

billing_from_archive() {
    local archive="$1" work="$2" arch="$3" entry name candidate
    local exact=() native=()
    tar -tzf "$archive" > "$work/members" || { billing_error "无法读取 $archive, 不回退覆盖上传包"; return 1; }
    while IFS= read -r entry || [ -n "$entry" ]; do
        case "$entry" in
            /*|[a-zA-Z]:*|../*|*/../*|*/..|..) billing_error "压缩包含不安全的路径: $entry"; return 1;;
        esac
        name="${entry##*/}"
        case "$name" in
            billing) exact+=("$entry");;
            "billing${arch%%:*}") native+=("$entry");;
        esac
    done < "$work/members"
    if [ "${#exact[@]}" = 1 ]; then
        candidate="${exact[0]}"
    elif [ "${#exact[@]}" = 0 ] && [ "${#native[@]}" = 1 ]; then
        candidate="${native[0]}"
    else
        billing_error "上传包需有唯一的 billing (或匹配架构的 billing${arch%%:*}) 普通程序文件"; return 1
    fi
    # Stream only the selected member; never unpack uploaded links or configuration.
    tar -xOzf "$archive" -- "$candidate" > "$work/new" || {
        billing_error "读取上传包中的程序失败: $candidate"; return 1;
    }
    billing_check_elf "$work/new" "$arch"
}

billing_prepare() (
    local project="$1" storage="$2" runtime="$3" upload="$4" backups="$5"
    local arch source="" origin="" work="" digest old_digest tag destination
    umask 077
    arch=$(billing_arch) || return 1
    if [ -L "$runtime" ] && [ ! -d "$runtime" ]; then
        billing_error "运行目录是失效链接: $runtime"; return 1
    fi
    if [ ! -e "$runtime" ]; then
        mkdir -p -- "$storage" "$(dirname -- "$runtime")" || return 1
        if [ "$(readlink -m -- "$storage")" != "$(readlink -m -- "$runtime")" ]; then
            ln -sT -- "$storage" "$runtime" || return 1
        fi
    fi
    [ -d "$runtime" ] || { billing_error "运行目录不是目录: $runtime"; return 1; }
    chmod go-w -- "$runtime" || return 1
    destination="$runtime/billing"
    # The former setini could create /home/billing/billing -> /tlgame/billing.
    if [ -d "$destination" ]; then
        if [ ! -L "$destination" ] || [ "$(cd -P -- "$destination" && pwd)" != "$(cd -P -- "$storage" && pwd)" ]; then
            billing_error "拒绝替换程序位置的目录: $destination"; return 1
        fi
    fi
    work=$(mktemp -d "$runtime/.billing.XXXXXX") || return 1
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [ -e "$upload" ] || [ -L "$upload" ]; then
        [ -f "$upload" ] || { billing_error "上传包不是普通文件: $upload"; return 1; }
        billing_from_archive "$upload" "$work" "$arch" || return 1
        origin="上传包 $upload (优先; 包内配置不覆盖现有配置)"
    else
        if [ -f "$destination" ]; then
            source="$destination"; origin="已有程序"
        elif [ -f "$storage/billing" ]; then
            source="$storage/billing"; origin="已有程序 $storage/billing"
        else
            case "${arch%%:*}" in
                32|64) :;;
                *) billing_error "无内置 ${arch%%:*} 程序, 请上传匹配系统架构的 $upload"; return 1;;
            esac
            source="$project/assets/billing/billing${arch%%:*}"
            [ -f "$project/assets/billing/SHA256SUMS" ] &&
                (cd "$project/assets/billing" && sha256sum --check --status SHA256SUMS) || {
                    billing_error "内置资源缺失或校验失败, 请更新 upcmd 后再次执行 upcmd 同步资源, 或上传 $upload"; return 1;
                }
            origin="环境内置 ${arch%%:*} 位程序"
        fi
        billing_check_elf "$source" "$arch" || return 1
        cp -- "$source" "$work/new" || return 1
    fi
    chmod 755 "$work/new" || return 1
    digest=$(sha256sum "$work/new") || return 1
    old_digest=""
    [ ! -f "$destination" ] || old_digest=$(sha256sum "$destination") || return 1
    if [ -L "$destination" ] || [ "${digest%% *}" != "${old_digest%% *}" ]; then
        if [ -f "$destination" ] || [ -L "$destination" ]; then
            mkdir -p -- "$backups" || return 1
            tag="$(date +%Y%m%d%H%M%S)-${work##*.}"
            cp -pP -- "$destination" "$backups/billing-before-$tag" || { billing_error "旧程序备份失败"; return 1; }
            printf 'Billing 旧程序备份: %s/billing-before-%s\n' "$backups" "$tag"
        fi
        mv -fT -- "$work/new" "$destination" || { billing_error "无法安装到 $destination"; return 1; }
    fi
    chmod 755 "$destination" || return 1
    printf 'Billing 程序已就绪: %s\nBilling 来源: %s\n' "$destination" "$origin"
    printf 'Billing SHA256: %s\n' "${digest%% *}"
    printf 'Billing 未自动启动; 执行【setini】写入配置后, 再执行【runtlbb】。\n'
)

billing_copy_missing() (
    local source="$1" target="$2" entry name
    shopt -s dotglob nullglob
    [ -d "$source" ] && [ -r "$source" ] && [ -x "$source" ] || return 1
    for entry in "$source"/*; do
        name="${entry##*/}"
        if [ -e "$target/$name" ] || [ -L "$target/$name" ]; then
            if [ -d "$entry" ] && [ ! -L "$entry" ] &&
                [ -d "$target/$name" ] && [ ! -L "$target/$name" ]; then
                billing_copy_missing "$entry" "$target/$name" || return 1
            fi
        else
            cp -a -- "$entry" "$target/$name" || return 1
        fi
    done
)

billing_prepare_native() {
    local project="$1" storage="$2" upload="$3" backups="$4" legacy="${5:-/home/billing}"
    local proc exe legacy_exe
    [ ! -L "$storage" ] || { billing_error "统一运行目录不能是符号链接: $storage"; return 1; }
    mkdir -p -- "$storage" || return 1
    if [ -d "$legacy" ] && [ "$(readlink -m -- "$legacy")" != "$(readlink -m -- "$storage")" ] &&
        [ ! -f "$storage/.legacy-imported" ]; then
        legacy_exe=$(readlink -m -- "$legacy/billing") || return 1
        for proc in /proc/[0-9]*/exe; do
            exe=$(readlink -- "$proc" 2>/dev/null) || continue
            if [ "${exe% (deleted)}" = "$legacy_exe" ]; then
                billing_error "旧目录 $legacy 的 Billing 仍在运行，请先关服，再迁移到 $storage"
                return 1
            fi
        done
        # Preserve existing canonical files and retain the entire legacy tree.
        # Never delete old credentials/logs or replace them with package defaults.
        billing_copy_missing "$legacy" "$storage" || { billing_error "旧目录复制失败，原目录未删除"; return 1; }
        touch "$storage/.legacy-imported" || return 1
        chmod 600 "$storage/.legacy-imported" || return 1
        printf 'Billing 旧数据已复制到 %s (已有同名文件优先保留)，原目录 %s 未删除。\n' "$storage" "$legacy"
    fi
    if [ -f "$storage/config.yaml" ] && [ ! -L "$storage/config.yaml" ]; then
        chmod 600 "$storage/config.yaml" || return 1
    fi
    billing_prepare "$project" "$storage" "$storage" "$upload" "$backups"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    printf '%s\n' '这是 Billing 公共部署组件, 请使用 untar 或 setini。' >&2
    exit 2
fi
