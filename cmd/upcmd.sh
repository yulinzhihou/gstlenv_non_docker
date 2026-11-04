#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum: https://gsgameshare.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker
# Date: 2026-11-04
# Update commands only; never run install.sh or modify runtime credentials/data.

upcmd_error() {
    printf '命令更新失败: %s\n' "$*" >&2
    printf '%s\n' '问题反馈: https://gitee.com/yulinzhihou/gstlenv_non_docker/issues' >&2
}

upcmd_validate() {
    local dir="$1" file name assets
    for name in upcmd untar setini color gs gsctl; do
        [ -f "$dir/$name.sh" ] && [ ! -L "$dir/$name.sh" ] || {
            upcmd_error "命令包缺少普通文件: $name.sh"; return 1;
        }
    done
    for file in "$dir"/*.sh; do
        name="${file##*/}"
        [[ "$name" =~ ^[a-z][a-z0-9-]*\.sh$ ]] && [ -f "$file" ] && [ ! -L "$file" ] || {
            upcmd_error "命令文件无效: $file"; return 1;
        }
        bash -n "$file" || { upcmd_error "语法检查未通过: $name"; return 1; }
    done
    if [ -f "$dir/billing-env.sh" ]; then
        assets="$(dirname -- "$dir")/assets/billing"
        for name in billing32 billing64 SHA256SUMS LICENSE README.md; do
            [ -f "$assets/$name" ] && [ ! -L "$assets/$name" ] || {
                upcmd_error "Billing 资源缺失: $assets/$name"; return 1;
            }
        done
        (cd "$assets" && sha256sum --check --status SHA256SUMS) || {
            upcmd_error "Billing 资源校验失败"; return 1;
        }
    fi
}

upcmd_download() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 180 --retry 1 "$url" -o "$output" && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 60 -t 2 -O "$output" "$url" && return 0
    fi
    return 1
}

upcmd_unpack() {
    local archive="$1" dir="$2" entry
    local roots=()
    mkdir -p "$dir" || return 1
    tar -tzf "$archive" > "$dir/members" || return 1
    while IFS= read -r entry || [ -n "$entry" ]; do
        case "$entry" in
            /*|../*|*/../*|*/..|..) upcmd_error "源码包路径不安全: $entry"; return 1;;
        esac
    done < "$dir/members"
    tar -xzf "$archive" --no-same-owner --no-same-permissions --keep-old-files -C "$dir" || return 1
    find "$dir" -mindepth 2 -maxdepth 2 -type d -name cmd -print0 > "$dir/commands" || return 1
    while IFS= read -r -d '' entry; do roots+=("$entry"); done < "$dir/commands"
    [ "${#roots[@]}" = 1 ] || { upcmd_error "源码包必须包含唯一的 cmd/ 目录"; return 1; }
    upcmd_validate "${roots[0]}" || return 1
    UPCMD_COMMAND_DIR="${roots[0]}"
}

upcmd_fetch() {
    local work="$1" url index=0 digest
    for url in \
        https://codeload.github.com/yulinzhihou/gstlenv_non_docker/tar.gz/refs/heads/main \
        https://gitee.com/yulinzhihou/gstlenv_non_docker/repository/archive/main.tar.gz; do
        index=$((index + 1))
        printf '下载命令源码: %s\n' "$url"
        if upcmd_download "$url" "$work/source-$index.tar.gz" &&
            upcmd_unpack "$work/source-$index.tar.gz" "$work/source-$index"; then
            digest=$(sha256sum "$work/source-$index.tar.gz") || return 1
            UPCMD_SOURCE="$url"
            printf '源码包 SHA256: %s\n' "${digest%% *}"
            return 0
        fi
        printf '该来源下载或校验失败, 尝试下一个来源。\n' >&2
    done
    upcmd_error "所有远程来源均失败; 未使用本机旧源码冒充更新。离线重部署请显式执行 upcmd --local"
    return 1
}

upcmd_deploy() (
    local source="$1" cmd_dir="$2" bin_dir="$3"
    local project_stage="" bin_stage="" file name path backup digest manifest_digest assets asset_target
    local committed=0 changed=0 i rollback_failed=0
    local destinations=() replacements=() backups=() files=() expected=() modes=()
    umask 077
    upcmd_validate "$source" || return 1
    mkdir -p "$cmd_dir" "$bin_dir" || return 1
    cmd_dir=$(cd -P -- "$cmd_dir" && pwd) || return 1
    bin_dir=$(cd -P -- "$bin_dir" && pwd) || return 1
    [ "$cmd_dir" != "$bin_dir" ] || { upcmd_error "源码与命令安装目录不能相同"; return 1; }
    case "$cmd_dir/" in "$bin_dir/"*) upcmd_error "源码与命令安装目录不能相互嵌套"; return 1;; esac
    case "$bin_dir/" in "$cmd_dir/"*) upcmd_error "源码与命令安装目录不能相互嵌套"; return 1;; esac
    project_stage=$(mktemp -d "$cmd_dir/.upcmd.XXXXXX") || return 1
    upcmd_cleanup() {
        local rc=$?
        trap - EXIT
        if [ "$committed" = 0 ]; then
            # Each attempted rename is recorded first, including interruption/failure.
            for ((i=changed-1; i>=0; i--)); do
                if [ -n "${backups[i]}" ]; then
                    mv -fT -- "${backups[i]}" "${destinations[i]}" || rollback_failed=1
                else
                    rm -f -- "${destinations[i]}" || rollback_failed=1
                fi
            done
        fi
        if [ "$rollback_failed" = 1 ]; then
            upcmd_error "回滚未完成, 请保留恢复文件: $project_stage $bin_stage"
            return 1
        fi
        rm -rf -- "$project_stage"
        [ -z "$bin_stage" ] || rm -rf -- "$bin_stage"
        return "$rc"
    }
    trap upcmd_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    bin_stage=$(mktemp -d "$bin_dir/.upcmd.XXXXXX") || return 1
    mkdir "$project_stage/new" "$project_stage/old" "$bin_stage/new" "$bin_stage/old" || return 1
    files=("$source"/*.sh)
    for file in "${files[@]}"; do
        name="${file##*/}"
        install -m 755 -- "$file" "$project_stage/new/$name" &&
            install -m 755 -- "$file" "$bin_stage/new/${name%.sh}" || {
                upcmd_error "准备命令文件失败: $name"; return 1;
            }
        destinations+=("$cmd_dir/$name" "$bin_dir/${name%.sh}")
        replacements+=("$project_stage/new/$name" "$bin_stage/new/${name%.sh}")
        digest=$(sha256sum "$project_stage/new/$name") || return 1
        expected+=("${digest%% *}" "${digest%% *}")
        modes+=(755 755)
        for path in "$cmd_dir/$name" "$bin_dir/${name%.sh}"; do
            backup=""
            if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
                upcmd_error "拒绝覆盖非普通文件: $path"; return 1
            fi
            if [ -f "$path" ]; then
                case "$path" in
                    "$cmd_dir/"*) backup="$project_stage/old/$name";;
                    *) backup="$bin_stage/old/$name";;
                esac
                cp -p -- "$path" "$backup" || { upcmd_error "备份命令失败: $path"; return 1; }
            fi
            backups+=("$backup")
        done
    done
    if [ -f "$source/billing-env.sh" ]; then
        assets="$(dirname -- "$source")/assets/billing"
        asset_target="$(dirname -- "$cmd_dir")/assets/billing"
        if [ -L "$(dirname -- "$asset_target")" ] || [ -L "$asset_target" ]; then
            upcmd_error "Billing 资源目录不能是符号链接: $asset_target"; return 1
        fi
        mkdir -p "$asset_target" "$project_stage/new/assets" "$project_stage/old/assets" || return 1
        for name in billing32 billing64 SHA256SUMS LICENSE README.md; do
            path="$asset_target/$name"
            if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
                upcmd_error "拒绝覆盖非普通 Billing 资源: $path"; return 1
            fi
            install -m 644 -- "$assets/$name" "$project_stage/new/assets/$name" || return 1
            backup=""
            if [ -f "$path" ]; then
                backup="$project_stage/old/assets/$name"
                cp -p -- "$path" "$backup" || return 1
            fi
            destinations+=("$path")
            replacements+=("$project_stage/new/assets/$name")
            backups+=("$backup")
            digest=$(sha256sum "$project_stage/new/assets/$name") || return 1
            expected+=("${digest%% *}")
            modes+=(644)
        done
    fi
    (cd "$project_stage/new" && sha256sum -- *.sh) > "$project_stage/manifest" || return 1
    manifest_digest=$(sha256sum "$project_stage/manifest") || return 1
    for ((i=0; i<${#destinations[@]}; i++)); do
        changed=$((i + 1))
        mv -fT -- "${replacements[i]}" "${destinations[i]}" || {
            upcmd_error "安装失败, 正在恢复旧命令: ${destinations[i]}"; return 1;
        }
    done
    for ((i=0; i<${#destinations[@]}; i++)); do
        digest=$(sha256sum "${destinations[i]}") || {
            upcmd_error "无法校验已安装命令, 正在恢复旧命令: ${destinations[i]}"; return 1;
        }
        [ "${digest%% *}" = "${expected[i]}" ] &&
            [ "$(stat -c %a "${destinations[i]}")" = "${modes[i]}" ] || {
            upcmd_error "安装后校验失败, 正在恢复旧命令: ${destinations[i]}"; return 1;
        }
    done
    digest=$(sha256sum "$bin_dir/untar") || return 1
    committed=1
    printf '命令清单 SHA256: %s\n' "${manifest_digest%% *}"
    printf '已校验 %s 个命令; 本地源码: %s; 安装目录: %s\n' "${#files[@]}" "$cmd_dir" "$bin_dir"
    [ -z "${asset_target:-}" ] || printf 'Billing 内置资源已同步并校验: %s (不替换正在使用的程序或配置)\n' "$asset_target"
    printf 'untar SHA256: %s\n' "${digest%% *}"
)

upcmd_main() (
    local mode=online project cmd_dir work="" resolved
    { export LANG=C.UTF-8 LC_ALL=C.UTF-8; } 2>/dev/null
    case "${1:-}" in
        --help|-h)
            printf '%s\n' '用法: upcmd [--online|--local]' \
                '默认在线下载原生项目 main 分支, 校验后更新命令、本地 cmd/ 及 Billing 内置资源。' \
                '--local: 不联网, 仅校验并重新部署本地 cmd/; 不表示获取了远程更新。'
            return 0;;
        ''|--online) :;;
        --local) mode=local;;
        *) upcmd_error "未知参数: $1; 用法: upcmd [--online|--local]"; return 2;;
    esac
    [ "$#" -le 1 ] || { upcmd_error "参数过多"; return 2; }
    [ "$(id -u)" = 0 ] || { upcmd_error "请使用 root 用户执行"; return 1; }
    if [ -f /root/.gs/.env ]; then
        source /root/.gs/.env || { upcmd_error "读取 /root/.gs/.env 失败"; return 1; }
    fi
    project="${GS_PROJECT:-/root/.tlgame}"
    case "$project" in
        /*) :;;
        *) upcmd_error "GS_PROJECT 必须是绝对路径"; return 1;;
    esac
    cmd_dir="${project%/}/cmd"
    command -v flock >/dev/null 2>&1 || { upcmd_error "缺少 flock (util-linux), 无法安全锁定更新"; return 1; }
    mkdir -p /usr/local/bin || return 1
    umask 077
    [ ! -L /usr/local/bin/.gs-upcmd.lock ] || { upcmd_error "更新锁不能是符号链接"; return 1; }
    exec 9>/usr/local/bin/.gs-upcmd.lock || return 1
    flock -n 9 || { upcmd_error "另一命令更新正在进行, 请稍后再试"; return 1; }
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [ "$mode" = online ]; then
        upcmd_fetch "$work" || return 1
        printf '更新来源: %s\n' "$UPCMD_SOURCE"
    else
        UPCMD_COMMAND_DIR="$cmd_dir"
        printf '本地重部署 (未联网获取更新): %s\n' "$cmd_dir"
    fi
    upcmd_deploy "$UPCMD_COMMAND_DIR" "$cmd_dir" /usr/local/bin || return 1
    if [ "$mode" = online ]; then
        printf '在线命令更新成功。输入 gs 查看帮助。\n'
    else
        printf '本地命令重部署成功 (不代表远程代码已更新)。\n'
    fi
    printf '解压命令安装位置: /usr/local/bin/untar\n'
    resolved=$(type -P untar) || resolved=""
    if [ "$resolved" != /usr/local/bin/untar ]; then
        printf '警告: 当前 PATH 首选 untar 为 %s; 请检查 type -a untar, 或直接执行 /usr/local/bin/untar。\n' "${resolved:-未找到}" >&2
    fi
    printf '当前终端请执行 hash -r; type -a untar, 检查是否有别名、函数或旧路径遮蔽。\n'
)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    upcmd_main "$@"
fi
