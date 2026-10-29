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

# comment: 一键开服，适合于那种可以一键开启的服务端，如果3-5分钟后，服务端没开启，则需要使用分步开服方式
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_HOME="${TLBB_HOME:-/tlgame}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"

# 检测是否已开服
SERVER_IS_RUN=$(pgrep -x Server 2>/dev/null | wc -l)
WORLD_IS_RUN=$(pgrep -x World 2>/dev/null | wc -l)
LOGIN_IS_RUN=$(pgrep -x Login 2>/dev/null | wc -l)
SHAREMEM_IS_RUN=$(pgrep -x ShareMemory 2>/dev/null | wc -l)
BILLING_IS_RUN=$(pgrep -x billing 2>/dev/null | wc -l)
echo "${CSUCCESS}正在检测是否已经开服……，请稍候……${CEND}"
if [ ${SERVER_IS_RUN} -ge 1 ] || [ ${WORLD_IS_RUN} -ge 1 ] || [ ${LOGIN_IS_RUN} -ge 1 ] || [ ${SHAREMEM_IS_RUN} -ge 1 ] || [ ${BILLING_IS_RUN} -ge 1 ]; then
    echo "${CRED}服务端好像正在运行，如果有疑问可以使用 [runtop] 进行查看，如果想继续执行，请先执行 [restart] 重启后再进行开服 [runtlbb] 操作${CEND}"
    exit 1
else
    echo "${CSUCCESS}暂未发现之前运行过，正在开启……${CEND}"
    # 检查数据库是否初始化成功
    if ! mysqladmin ping >/dev/null 2>&1; then
        echo "${CRED}环境未被初始化成功，请执行 [rebuild] 命令，进行重构${CEND}"
        exit 1
    fi
    if [ ! -f "${TLBB_PATH}/run.sh" ]; then
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}未找到服务端启动脚本 ${TLBB_PATH}/run.sh，请确认已经执行【untar】【setini】操作！${CEND}"
        exit 1
    fi
    chmod -R 777 ${TLBB_HOME} &&
        cd ${TLBB_PATH} &&
        nohup bash run.sh >/dev/null 2>&1 &

    if [ $? -eq 0 ]; then
        # 删除因为改版本导致引擎启动失败的dump文件
        cd ${TLBB_HOME} && rm -rf core.* 2>/dev/null

        # 启动日志备份定时任务
        if [ -f /usr/local/bin/logbak ]; then
            /bin/bash /usr/local/bin/logbak cron 1 10 >/dev/null 2>&1
            echo -e "${CYELLOW}已自动启动日志备份定时任务，默认1小时备份一次，保留10份${CEND}"
        fi

        echo -e "${CSUCCESS}已经成功启动服务端，请耐心等待几分钟后，建议使用：【runtop】查看开服的情况！！${CEND}"
        echo -e "${CWARNING}如果需要定时备份，请执行【gsbak】命令，默认1小时备份一次数据库和版本，保留10次备份数据！！${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED} 启动服务端失败！${CEND}"
        exit 1
    fi
fi
