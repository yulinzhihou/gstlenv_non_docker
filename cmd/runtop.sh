#!/usr/bin/env bash
# Project: https://github.com/yulinzhihou/gstlenv_non_docker
# Read-only run.sh process monitor. Never source or execute the startup script.

runtop_usage() {
    cat <<'HELP'
用法: runtop [--once] [--interval 秒]
  默认每 2 秒刷新 run.sh 的启动进程; q/Q 或 Ctrl+C 退出。
  --once          只输出一次快照; 管道、重定向时自动使用此模式
  --interval N    刷新间隔，整数 1-60 秒
  -h, --help      查看帮助
状态: RUN=运行中, STOP=未运行, MISSING=程序文件缺失/不可执行。
CPU% 为采样区间占用率，单核满载为 100%，多线程可超过 100%。
HELP
}

runtop_load_targets() {
    local file="$1" root="$2" helper loaded=0 index path row name
    for helper in "$(dirname -- "${BASH_SOURCE[0]}")/run-env.sh" /usr/local/bin/run-env "${GS_PROJECT:-/root/.tlgame}/cmd/run-env.sh"; do
        [ -f "$helper" ] || continue
        source "$helper" || return 1
        loaded=1; break
    done
    [ "$loaded" = 1 ] || { echo '缺少启动脚本解析组件，请执行 upcmd。' >&2; return 1; }
    run_load "$file" "$root" || return 1
    RUNTOP_NAMES=(); RUNTOP_PATHS=(); RUNTOP_INDEX=()
    RUNTOP_WARNINGS="${#RUN_ERRORS[@]}"; RUNTOP_WARNING="${RUN_ERRORS[0]:-}"
    for index in "${!RUN_NAMES[@]}"; do
        path="${RUN_MONITORS[index]}"
        row="${RUNTOP_INDEX[$path]:-}"
        if [ -z "$row" ]; then
            row="${#RUNTOP_PATHS[@]}"; name="${path##*/}"
            [ "${RUN_ROLES[index]}" != ShareMemory ] || name=ShareMemory
            RUNTOP_NAMES+=("$name"); RUNTOP_PATHS+=("$path"); RUNTOP_INDEX["$path"]="$row"
        fi
        RUNTOP_INDEX["${RUN_EXES[index]}"]="$row"
    done
    [ "${#RUNTOP_PATHS[@]}" -gt 0 ] || {
        printf 'run.sh 中未识别到可监控的直接启动项 (./程序或绝对路径)。\n' >&2
        [ -z "$RUNTOP_WARNING" ] || printf '提示: %s\n' "$RUNTOP_WARNING" >&2
        return 1
    }
}

runtop_script_index() {
    local pid="$1" arg cwd count=0
    RUNTOP_MATCH=""
    # Interpreted programs have the interpreter in /proc/PID/exe. Match only a
    # literal script argument, never a substring of arbitrary command arguments.
    while IFS= read -r -d '' arg; do
        count=$((count + 1))
        [ "$count" -gt 1 ] || continue
        case "$arg" in -c|--) return 0;; -*) continue;; esac
        cwd=$(readlink -- "/proc/$pid/cwd") || return 0
        case "$arg" in /*) ;; *) arg="$cwd/$arg";; esac
        arg=$(readlink -m -- "$arg") || return 0
        RUNTOP_MATCH="${RUNTOP_INDEX[$arg]:-}"
        return 0
    done 2>/dev/null < "/proc/$pid/cmdline" || true
}

runtop_collect() {
    local proc exe pid index stat rest ticks start key state rss metrics row
    local uptime idle old_ticks old_time fields=()
    RUNTOP_ROWS=(); RUNTOP_ACTIVE=(); RUNTOP_PROCESS_COUNT=0
    local -A next_ticks=() next_times=()
    read -r uptime idle < /proc/uptime
    while IFS=$'\t' read -r proc exe; do
        pid="${proc##*/}"
        exe="${exe% (deleted)}"
        [ -n "$exe" ] || continue
        index="${RUNTOP_INDEX[$exe]:-}"
        if [ -z "$index" ]; then
            case "${exe##*/}" in
                bash|sh|dash|python|python[0-9]*|perl)
                    runtop_script_index "$pid"
                    index="$RUNTOP_MATCH";;
            esac
        fi
        [ -n "$index" ] || continue
        IFS= read -r stat 2>/dev/null < "$proc/stat" || continue
        rest="${stat##*) }"
        read -r -a fields <<< "$rest"
        [ "${#fields[@]}" -ge 22 ] || continue
        state="${fields[0]}"
        ticks=$((${fields[11]} + ${fields[12]}))
        start="${fields[19]}"
        key="$pid:$start"
        old_ticks="${RUNTOP_PREV_TICKS[$key]:-}"
        old_time="${RUNTOP_PREV_TIMES[$key]:-}"
        rss=$((${fields[21]} * RUNTOP_PAGE_KB))
        metrics=$(awk -v now="$uptime" -v before="$old_time" -v ticks="$ticks" \
            -v old="$old_ticks" -v hz="$RUNTOP_HZ" -v start="$start" \
            -v rss="$rss" -v total="$RUNTOP_MEM_KB" 'BEGIN {
                cpu = "--"
                if (before != "" && now > before && ticks >= old)
                    cpu = sprintf("%.1f", 100 * (ticks - old) / hz / (now - before))
                seconds = int(now - start / hz); if (seconds < 0) seconds = 0
                printf "%7s %6.1f %9.1f %3dd%02d:%02d:%02d", cpu,
                    100 * rss / total, rss / 1024, int(seconds / 86400),
                    int(seconds / 3600) % 24, int(seconds / 60) % 60, seconds % 60
            }')
        printf -v row '%-16.16s %-8s %7s %s' "${RUNTOP_NAMES[index]}" "RUN/$state" "$pid" "$metrics"
        RUNTOP_ROWS["$index"]+="$row"$'\n'
        RUNTOP_ACTIVE["$index"]=1
        RUNTOP_PROCESS_COUNT=$((RUNTOP_PROCESS_COUNT + 1))
        next_ticks["$key"]="$ticks"; next_times["$key"]="$uptime"
    done < <(find /proc -mindepth 2 -maxdepth 2 -path '/proc/[0-9]*/exe' -printf '%h\t%l\n' 2>/dev/null)
    RUNTOP_PREV_TICKS=(); RUNTOP_PREV_TIMES=()
    for key in "${!next_ticks[@]}"; do
        RUNTOP_PREV_TICKS["$key"]="${next_ticks[$key]}"
        RUNTOP_PREV_TIMES["$key"]="${next_times[$key]}"
    done
}

runtop_render() {
    local file="$1" interval="$2" interactive="$3" index row status shown=0 hidden=0
    local lines=24 columns=80 limit=100000
    if [ "$interactive" = 1 ]; then
        read -r lines columns < <(stty size 2>/dev/null) || true
        [[ "$lines" =~ ^[0-9]+$ ]] && [ "$lines" -gt 12 ] || lines=24
        [[ "$columns" =~ ^[0-9]+$ ]] && [ "$columns" -gt 20 ] || columns=80
        limit=$((lines - 9))
        printf '\033[H\033[2J'
    fi
    printf 'GS游享网 | run.sh 进程监控 | %s\n' "$(date '+%F %T')"
    printf '启动脚本: %.*s\n' "$((columns - 12))" "$file"
    printf '启动项: %s | 运行项: %s | 进程: %s | 刷新: %ss\n' \
        "${#RUNTOP_PATHS[@]}" "${#RUNTOP_ACTIVE[@]}" "$RUNTOP_PROCESS_COUNT" "$interval"
    printf 'q:退出  r:刷新 | CPU%%:区间采样/单核100%% | --:等待下次采样\n'
    printf '%-16s %-8s %7s %7s %6s %9s %12s\n' PROCESS STATUS PID CPU% MEM% 'RSS(MiB)' ELAPSED
    for index in "${!RUNTOP_PATHS[@]}"; do
        if [ -z "${RUNTOP_ACTIVE[$index]:-}" ]; then
            status=STOP
            [ -x "${RUNTOP_PATHS[index]}" ] || status=MISSING
            printf -v row '%-16.16s %-8s %7s %7s %6s %9s %12s' \
                "${RUNTOP_NAMES[index]}" "$status" - - - - -
            RUNTOP_ROWS["$index"]="$row"$'\n'
        fi
        while IFS= read -r row; do
            [ -n "$row" ] || continue
            if [ "$shown" -lt "$limit" ]; then printf '%s\n' "$row"; else hidden=$((hidden + 1)); fi
            shown=$((shown + 1))
        done <<< "${RUNTOP_ROWS[$index]}"
    done
    printf 'RUN=运行 STOP=停止 MISSING=文件缺失/不可执行\n'
    printf '仅检查进程; 开服结果请结合日志和实际登录测试。\n'
    [ "$hidden" = 0 ] || printf '另有 %s 行未显示，请用 runtop --once 查看完整快照。\n' "$hidden"
    [ "$RUNTOP_WARNINGS" = 0 ] || printf '解析提示 (%s): %.*s\n' "$RUNTOP_WARNINGS" "$((columns - 18))" "$RUNTOP_WARNING"
    if [ "$interactive" = 0 ]; then
        printf '\n启动项路径:\n'
        for index in "${!RUNTOP_PATHS[@]}"; do
            printf '  %s: %s\n' "${RUNTOP_NAMES[index]}" "${RUNTOP_PATHS[index]}"
        done
    fi
    if [ "$interactive" = 1 ]; then printf '\033[J'; fi
}

runtop_watch() {
    local root="$1" once="$2" interval="$3" file interactive=0 key rc tool
    local -a RUNTOP_NAMES=() RUNTOP_PATHS=()
    local -A RUNTOP_INDEX=() RUNTOP_VARS=() RUNTOP_PREV_TICKS=() RUNTOP_PREV_TIMES=()
    local -A RUNTOP_ROWS=() RUNTOP_ACTIVE=()
    local RUNTOP_WARNINGS=0 RUNTOP_WARNING="" RUNTOP_CWD="" RUNTOP_EXPANDED="" RUNTOP_RESOLVED="" RUNTOP_MATCH=""
    local RUNTOP_HZ RUNTOP_PAGE_KB RUNTOP_MEM_KB RUNTOP_PROCESS_COUNT
    for tool in awk find readlink getconf date sleep stty; do
        command -v "$tool" >/dev/null 2>&1 || {
            printf '缺少监控所需命令: %s\n' "$tool" >&2; return 1;
        }
    done
    root=$(readlink -m -- "$root") || return 1
    file="$root/run.sh"
    runtop_load_targets "$file" "$root" || return 1
    RUNTOP_HZ=$(getconf CLK_TCK) || return 1
    RUNTOP_PAGE_KB=$(( $(getconf PAGESIZE) / 1024 ))
    RUNTOP_MEM_KB=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
    [[ "$RUNTOP_MEM_KB" =~ ^[1-9][0-9]*$ ]] || { echo '无法读取 Linux /proc 内存信息。' >&2; return 1; }
    if [ "$once" = 0 ] && [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then
        interactive=1
        trap 'printf "\033[?25h\033[?1049l"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP
        printf '\033[?1049h\033[?25l\033[2J'
    fi
    runtop_collect
    sleep 0.2
    while :; do
        runtop_collect
        runtop_render "$file" "$interval" "$interactive"
        [ "$interactive" = 1 ] || break
        key=""
        if read -r -s -n 1 -t "$interval" key; then
            case "$key" in q|Q) break;; esac
        else
            rc=$?
            [ "$rc" -gt 128 ] || break
        fi
    done
    if [ "$interactive" = 1 ]; then
        printf '\033[?25h\033[?1049l'
        trap - EXIT INT TERM HUP
    fi
}

runtop_main() {
    local once=0 interval=2
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --once) once=1;;
            --interval)
                shift
                [[ "${1:-}" =~ ^([1-9]|[1-5][0-9]|60)$ ]] || {
                    echo '刷新间隔必须是 1-60 的整数秒。' >&2; return 2;
                }
                interval="$1";;
            -h|--help) runtop_usage; return 0;;
            *) printf '未知参数: %s\n' "$1" >&2; runtop_usage >&2; return 2;;
        esac
        shift
    done
    if [ ! -f /root/.gs/.env ]; then
        echo '环境未初始化，请先安装环境。' >&2; return 1
    fi
    . /root/.gs/.env
    runtop_watch "${TLBB_PATH:-/tlgame/tlbb}" "$once" "$interval"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    runtop_main "$@"
fi
