#!/usr/bin/env bash
# 设置字符编码，确保中文正常显示
{
    export LANG=C.UTF-8 2>/dev/null || export LANG=en_US.UTF-8 2>/dev/null || export LANG=POSIX 2>/dev/null || true
    export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX 2>/dev/null || true
} 2>/dev/null
# 引入全局参数
[ -f /root/.gs/.env ] && . /root/.gs/.env
# 颜色代码
[ -f /usr/local/bin/color ] && . /usr/local/bin/color

# comment: 分步调试开服 (参考 gstlenv step.sh, 原生版)
# 解析 /tlgame/tlbb/run.sh, 逐步启动服务端进程
# 用法:
#   step          交互式选择启动步骤
#   step 1        启动第 1 步 (billing 存在时先启动 billing)
#   step 2...N    启动对应进程 (Login/Center/World/Server 等)
# ============================================================
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
RUN_SH_FILE="$TLBB_PATH/run.sh"
TLBB_SERVER_DIR="$TLBB_PATH/Server"

[ -d "$TLBB_PATH" ] || { echo "${CRED}请先解压服务端(untar), 再使用此命令${CEND}"; exit 1; }

# 解析 run.sh 提取启动命令
parse_run_sh() {
    local run_file="$1"
    local steps=()
    local current_cd=""
    local current_export=""

    [ -f "$run_file" ] || { echo "${CRED}错误: 找不到 run.sh 文件: ${run_file}${CEND}" >&2; return 1; }

    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | sed 's/[[:space:]]*$//')
        [[ -z "$line" ]] && continue
        # 跳过纯注释
        [[ "$line" =~ ^[[:space:]]*#+[[:space:]]*$ ]] && continue
        # 排除 billing 命令
        [[ "$line" =~ [Bb][Ii][Ll][Ll][Ii][Nn][Gg] ]] && continue
        # 提取 cd
        if [[ "$line" =~ cd[[:space:]]+([^;&|>]+) ]]; then
            current_cd=$(echo "${BASH_REMATCH[1]}" | xargs)
            continue
        fi
        # 提取 export
        if [[ "$line" =~ export[[:space:]]+([^;&|>]+) ]]; then
            current_export="export ${BASH_REMATCH[1]}"
            continue
        fi
        # 查找启动命令 ./程序名
        if [[ "$line" =~ \.\/([^[:space:]]+)([[:space:]]*.*)? ]]; then
            local prog_name="${BASH_REMATCH[1]}"
            local rest_line="${BASH_REMATCH[2]}"
            # 排除压缩包
            [[ "$prog_name" =~ \.(tar|gz|zip|rar|7z|bz2|xz)$ ]] && continue
            # 排除 shm clear
            [[ "$prog_name" == "shm" ]] && [[ "$rest_line" =~ clear ]] && continue
            # 清理重定向与后台符号
            rest_line=$(echo "$rest_line" | sed 's/[[:space:]]*>[[:space:]]*\/dev\/null[[:space:]]*2>&1[[:space:]]*&[[:space:]]*$//')
            rest_line=$(echo "$rest_line" | sed 's/[[:space:]]*&[[:space:]]*$//')
            rest_line=$(echo "$rest_line" | xargs)

            local cmd_parts=()
            [ -n "$current_export" ] && cmd_parts+=("$current_export")
            [ -n "$current_cd" ] && cmd_parts+=("cd ${current_cd}")
            if [ -n "$rest_line" ] && [[ "$rest_line" != "start" ]]; then
                cmd_parts+=("./${prog_name} ${rest_line}")
            elif [[ "$prog_name" == "shm" ]] && [[ "$rest_line" == "start" ]]; then
                cmd_parts+=("./${prog_name} ${rest_line}")
            else
                cmd_parts+=("./${prog_name}")
            fi
            local full_cmd; full_cmd=$(IFS=' && '; echo "${cmd_parts[*]}")
            # 检查程序存在
            local prog_path=""
            if [ -n "$current_cd" ]; then prog_path="${current_cd}/${prog_name}"; else prog_path="${TLBB_SERVER_DIR}/${prog_name}"; fi
            if [[ "$prog_name" == "shm" ]] || [ -f "$prog_path" ] || [ -x "$prog_path" ] 2>/dev/null; then
                local exists=0
                for existing in "${steps[@]}"; do
                    [[ "$existing" == "$full_cmd" ]] && { exists=1; break; }
                done
                [ $exists -eq 0 ] && steps+=("$full_cmd")
            fi
            current_export=""
        fi
    done <"$run_file"

    printf '%s\n' "${steps[@]}"
}

# 执行 billing (可选)
run_billing() {
    if [ -d /home/billing ] && [ -f /home/billing/billing ]; then
        cd /home/billing
        ./billing stop 2>/dev/null
        ./billing up -d && echo "${CSUCCESS}启动 [BILLING] 服务成功, 请耐心等待几分钟. 建议使用【 runtop 】查看情况!!${CEND}" && return 0
        echo "${CRED}启动 [BILLING] 服务失败!${CEND}"
        return 1
    fi
    echo "${CWARNING}未找到 billing 程序 (/home/billing/billing), 跳过 billing 启动${CEND}"
    return 0
}

get_step_name() {
    local cmd="$1"
    if [[ "$cmd" =~ \.\/([^[:space:]&]+) ]]; then
        local prog="${BASH_REMATCH[1]}"
        [[ "$prog" == "shm" ]] && echo "ShareMemory" || echo "$prog"
    else
        echo "Unknown"
    fi
}

run_step() {
    local num="$1" cmd="$2"
    echo "${CYELLOW}正在执行步骤 ${num}: $(get_step_name "$cmd")${CEND}"
    echo "${CYELLOW}执行命令: ${cmd}${CEND}"
    eval "$cmd"
    if [ $? -eq 0 ]; then
        echo "${CSUCCESS}启动 [$(get_step_name "$cmd")] 服务成功, 请耐心等待几分钟. 建议使用【 runtop 】查看情况!!${CEND}"
        return 0
    fi
    echo "${CRED}启动 [$(get_step_name "$cmd")] 服务失败!${CEND}"
    return 1
}

# 主流程
main() {
    local steps=()
    while IFS= read -r line; do [ -n "$line" ] && steps+=("$line"); done < <(parse_run_sh "$RUN_SH_FILE")
    if [ ${#steps[@]} -eq 0 ]; then
        echo "${CRED}错误: 无法从 run.sh 中解析出启动命令!${CEND}"
        exit 1
    fi

    local has_billing=0
    [ -d /home/billing ] && [ -f /home/billing/billing ] && has_billing=1

    # 单参数: 直接执行指定步骤
    if [ $# -eq 1 ]; then
        local step_num="$1"
        if [ "$step_num" -eq 1 ] || [[ "$step_num" =~ ^[Bb]$ ]] || [[ "$step_num" == "billing" ]]; then
            if [ $has_billing -eq 1 ]; then run_billing; exit $?; fi
            echo "${CWARNING}未找到 billing 服务, 跳过第一步${CEND}"
            exit 0
        fi
        local actual=$step_num
        [ $has_billing -eq 1 ] && actual=$((step_num - 1))
        if [ $actual -ge 1 ] && [ $actual -le ${#steps[@]} ]; then
            run_step "$step_num" "${steps[$((actual - 1))]}"
            exit $?
        fi
        echo "${CRED}错误: 步骤编号 ${step_num} 无效! 有效范围: 1-$((has_billing + ${#steps[@]}))${CEND}"
        exit 1
    fi

    # 交互式
    echo "${CRED}注意: 执行此命令前, 建议重启服务器, 避免一些不必要的问题!${CEND}"
    echo "${CYELLOW}请使用多个终端窗口分别启动每个服务, 一共需要 $((has_billing + ${#steps[@]})) 个窗口${CEND}"
    while :; do
        echo ""
        echo "${CYELLOW}※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※${CEND}"
        echo "${CYELLOW}◎ 请使用 runtop 命令查看开启了哪些进程${CEND}"
        echo "${CYELLOW}◎ 请不要重复启动, 重复启动没有任何意义${CEND}"
        echo ""
        local idx=1
        if [ $has_billing -eq 1 ]; then
            echo "${CYELLOW}◎ 步骤[${idx}|b|billing]：启动 [BILLING] 服务${CEND}"
            idx=$((idx + 1))
        fi
        for i in "${!steps[@]}"; do
            echo "${CYELLOW}◎ 步骤[${idx}]：启动 [$(get_step_name "${steps[$i]}")] 服务${CEND}"
            echo "${CCYAN}   命令：${steps[$i]}${CEND}"
            idx=$((idx + 1))
        done
        echo "${CYELLOW}※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※${CEND}"
        read -e -p "${CYELLOW}请选择功能 输入序号并回车: ${CEND}" num
        if [[ "$num" =~ ^[Bb]$ ]] || { [ "$num" = "1" ] && [ $has_billing -eq 1 ]; }; then
            run_billing; break
        fi
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            local actual=$num
            [ $has_billing -eq 1 ] && actual=$((num - 1))
            if [ $actual -ge 1 ] && [ $actual -le ${#steps[@]} ]; then
                run_step "$num" "${steps[$((actual - 1))]}"
                break
            fi
            echo "${CRED}输入错误! 请输入有效的步骤编号!${CEND}"
        else
            echo "${CRED}输入错误! 请输入数字或 b/billing!${CEND}"
        fi
    done
}

main "$@"
