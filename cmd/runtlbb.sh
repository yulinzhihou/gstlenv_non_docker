#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 一键开服，适合于那种可以一键开启的服务端，如果3-5分钟后，服务端没开启，则需要使用分步开服方式

# 设置字符编码，确保中文正常显示
{
    export LANG=C.UTF-8 2>/dev/null || export LANG=en_US.UTF-8 2>/dev/null || export LANG=POSIX 2>/dev/null || true
    export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX 2>/dev/null || true
} 2>/dev/null
# 引入全局参数
[ -f /root/.gs/.env ] && . /root/.gs/.env
# 颜色代码
[ -f /usr/local/bin/color ] && . /usr/local/bin/color

if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_HOME="${TLBB_HOME:-/tlgame}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
run_loaded=0
for run_helper in "$(dirname -- "${BASH_SOURCE[0]}")/run-env.sh" /usr/local/bin/run-env "${GS_PROJECT:-/root/.tlgame}/cmd/run-env.sh"; do
    [ -f "$run_helper" ] || continue
    source "$run_helper" || exit 1
    run_loaded=1; break
done
[ "$run_loaded" = 1 ] || { echo '缺少启动检查组件，请执行 upcmd。'; exit 1; }
run_native_paths || exit 1
run_load "$TLBB_PATH/run.sh" "$TLBB_PATH" &&
    run_validate "$TLBB_PATH" "$TLBB_HOME/billing" "$((1 - ${IS_DLQ:-0}))" || exit 1

export TLBB_HOME TLBB_PATH
echo "${CSUCCESS}正在检测是否已经开服……，请稍候……${CEND}"
for run_index in "${!RUN_NAMES[@]}"; do
    run_find_pids "$run_index"
    if [ "${#RUN_PIDS[@]}" -gt 0 ]; then
        printf '启动项 %s 已运行 (PID: %s)，不重复开服；可用 runtop 查看。\n' "${RUN_NAMES[run_index]}" "${RUN_PIDS[*]}"
        exit 1
    fi
done
echo "${CSUCCESS}暂未发现之前运行过，正在开启……${CEND}"
# 检查数据库是否初始化成功
if ! mysqladmin ping >/dev/null 2>&1; then
    echo "${CRED}数据库尚未就绪，请先检查 MySQL 服务及连接配置；不要直接重置数据库。${CEND}"
    exit 1
fi
cd "$TLBB_PATH" || exit 1
nohup bash run.sh >/dev/null 2>&1 &

if [ $? -eq 0 ]; then
    # 删除因为改版本导致引擎启动失败的dump文件
    cd "$TLBB_HOME" && rm -f -- core.* 2>/dev/null

    # 启动日志备份定时任务
    if [ -f /usr/local/bin/logbak ]; then
        /bin/bash /usr/local/bin/logbak cron 1 10 >/dev/null 2>&1
        echo -e "${CYELLOW}已自动启动日志备份定时任务，默认1小时备份一次，保留10份${CEND}"
    fi

    echo -e "${CSUCCESS}已提交 run.sh 后台启动请求，请等待后用【runtop】和【gslog】确认实际启动结果。${CEND}"
    echo -e "${CWARNING}如果需要定时备份，请执行【gsbak】命令，默认1小时备份一次数据库和版本，保留10次备份数据！！${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED} 启动服务端失败！${CEND}"
    exit 1
fi
