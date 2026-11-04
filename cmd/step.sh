#!/usr/bin/env bash
# Run one inspected startup command, without evaluating the original run.sh.

step_usage() {
    cat <<'HELP'
用法: step [编号|billing|--list|--check]
  step          列出实际程序、路径和命令，交互选择一个步骤
  step --list   仅查看启动清单，不启动程序
  step --check  检查 run.sh 的目录、程序和 LD_PRELOAD 文件
  step N        在当前终端前台运行第 N 个程序，便于查看启动错误
排序: Billing -> ShareMemory/shm -> Login -> World -> Server -> 其他程序。
Server1、Server_fix 等保留实际命令，归入 Server 角色，不重命名或覆盖文件。
HELP
}

step_run() {
    local root="$1" billing="$2" choice="${3:---list}" index number=1 pid
    run_load "$root/run.sh" "$root" || return 1
    run_order
    [ "${#RUN_ORDER[@]}" -gt 0 ] || { echo 'run.sh 未识别到启动程序，请先执行 setini 修复。' >&2; return 1; }
    if [ "$choice" = --check ]; then
        run_validate "$root" "$billing" "$((1 - ${IS_DLQ:-0}))" || return 1
        echo 'run.sh 路径、程序和启动依赖检查通过；未启动程序。'
        return 0
    fi
    if [ "$choice" = --list ] || [ "$choice" = interactive ]; then
        printf '启动脚本: %s/run.sh\n' "$root"
        for index in "${RUN_ORDER[@]}"; do
            printf '\nstep %s  [%s / %s]\n' "$number" "${RUN_ROLES[index]}" "${RUN_NAMES[index]}"
            run_describe "$index"
            number=$((number + 1))
        done
        [ "$choice" = interactive ] || return 0
        read -r -p '请输入步骤编号 (q 退出): ' choice || return 1
        case "$choice" in q|Q) return 0;; esac
    fi
    case "$choice" in
        billing|b|B)
            [ "${RUN_ROLES[${RUN_ORDER[0]}]}" = Billing ] || {
                echo 'run.sh 没有 Billing 启动项，请执行 setini 检查。' >&2; return 1;
            }
            choice=1;;
    esac
    [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "${#choice}" -le 6 ] &&
        [ "$choice" -le "${#RUN_ORDER[@]}" ] || {
        printf '步骤编号无效，有效范围: 1-%s\n' "${#RUN_ORDER[@]}" >&2; return 2;
    }
    run_validate "$root" "$billing" "$((1 - ${IS_DLQ:-0}))" || return 1
    index="${RUN_ORDER[choice-1]}"
    run_find_pids "$index"
    if [ "${#RUN_PIDS[@]}" -gt 0 ]; then
        printf '%s 已运行，PID: %s；不重复启动或自动停止。\n' "${RUN_NAMES[index]}" "${RUN_PIDS[*]}" >&2
        return 1
    fi
    printf '执行 step %s (前台调试，不执行 run.sh 中的 rm、内核设置或其他程序):\n' "$choice"
    run_describe "$index"
    if run_execute "$index"; then
        echo '该启动命令已退出 (退出码 0)；是否常驻成功请结合 runtop 和程序日志确认。'
    else
        local rc=$?
        printf '启动命令失败，退出码: %s\n' "$rc" >&2
        return "$rc"
    fi
}

step_main() {
    [ "$#" -le 1 ] || { step_usage >&2; return 2; }
    case "${1:-}" in -h|--help) step_usage; return 0;; esac
    [ -f /root/.gs/.env ] || { echo '环境未初始化，请先安装环境。' >&2; return 1; }
    source /root/.gs/.env || return 1
    local helper loaded=0
    for helper in "$(dirname -- "${BASH_SOURCE[0]}")/run-env.sh" /usr/local/bin/run-env "${GS_PROJECT:-/root/.tlgame}/cmd/run-env.sh"; do
        [ -f "$helper" ] || continue
        source "$helper" || return 1
        loaded=1; break
    done
    [ "$loaded" = 1 ] || { echo '缺少启动脚本解析组件，请先执行 upcmd。' >&2; return 1; }
    run_native_paths || return 1
    step_run "${TLBB_PATH:-/tlgame/tlbb}" "${TLBB_HOME:-/tlgame}/billing" "${1:-interactive}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then step_main "$@"; fi
