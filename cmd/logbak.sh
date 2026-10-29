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

# comment: 定时备份日志文件，默认1小时备份一次，保留10份
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
# 日志目录配置
LOG_DIR="${TLBB_PATH}/Server/Log"
LOGBAK_DIR="${TLBB_PATH}/logbak"
DEFAULT_INTERVAL=1  # 默认1小时备份一次
DEFAULT_KEEP_NUM=10 # 默认保留10份

# 解析参数
if [ "$1" == "cron" ] || [ "$1" == "setup" ]; then
    # 设置定时任务模式
    if [ $# -ge 2 ]; then
        case $2 in
        [1-9] | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24)
            INTERVAL=$2
            ;;
        *)
            INTERVAL=${DEFAULT_INTERVAL}
            ;;
        esac
    else
        INTERVAL=${DEFAULT_INTERVAL}
    fi

    if [ $# -ge 3 ]; then
        case $3 in
        [1-9] | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30)
            KEEP_NUM=$3
            ;;
        *)
            KEEP_NUM=${DEFAULT_KEEP_NUM}
            ;;
        esac
    else
        KEEP_NUM=${DEFAULT_KEEP_NUM}
    fi
else
    # 手动执行备份模式
    if [ $# -ge 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        INTERVAL=$1
    else
        INTERVAL=${DEFAULT_INTERVAL}
    fi

    if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
        KEEP_NUM=$2
    else
        KEEP_NUM=${DEFAULT_KEEP_NUM}
    fi
fi

# 确保日志目录存在
if [ ! -d "${LOG_DIR}" ]; then
    mkdir -p "${LOG_DIR}"
    echo -e "${CYELLOW}已自动创建日志目录：${LOG_DIR}${CEND}"
fi

# 确保备份目录存在
if [ ! -d "${LOGBAK_DIR}" ]; then
    mkdir -p "${LOGBAK_DIR}"
    echo -e "${CYELLOW}已自动创建日志备份目录：${LOGBAK_DIR}${CEND}"
fi

# 备份日志函数
backup_logs() {
    if [ ! "$(ls -A ${LOG_DIR} 2>/dev/null)" ]; then
        echo -e "${CWARNING}日志目录为空，无需备份${CEND}"
        return 0
    fi

    DIR=$(date +%Y%m%d-%H%M)
    mkdir -p "${LOGBAK_DIR}/${DIR}"

    if [ "$(ls -A ${LOG_DIR} 2>/dev/null)" ]; then
        mv ${LOG_DIR}/* "${LOGBAK_DIR}/${DIR}/" 2>/dev/null
        cd "${LOGBAK_DIR}"
        tar -czf "${DIR}.tar.gz" "${DIR}" 2>/dev/null
        rm -rf "${DIR}"

        if [ $? -eq 0 ]; then
            echo -e "${CSUCCESS}日志备份完成：${LOGBAK_DIR}/${DIR}.tar.gz${CEND}"
            return 0
        else
            echo -e "${CRED}日志备份失败！${CEND}"
            return 1
        fi
    else
        echo -e "${CWARNING}日志目录为空，无需备份${CEND}"
        return 0
    fi
}

# 清理旧备份函数
cleanup_old_backups() {
    if [ ${KEEP_NUM} -eq 0 ]; then
        echo -e "${CWARNING}保留份数设置为0，跳过清理${CEND}"
        return 0
    fi

    FILE_CUR_NUM=$(ls -ltr "${LOGBAK_DIR}" | grep "\.tar\.gz$" | wc -l)

    if [ ${FILE_CUR_NUM} -gt ${KEEP_NUM} ]; then
        let NUM_DEL=${FILE_CUR_NUM}-${KEEP_NUM}
        cd "${LOGBAK_DIR}" &&
            ls -ltr | grep "\.tar\.gz$" | awk '{print $9}' | head -n ${NUM_DEL} | xargs rm -rf 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${CSUCCESS}已清理 ${NUM_DEL} 个旧备份文件，保留最新 ${KEEP_NUM} 份${CEND}"
        fi
    else
        echo -e "${CYELLOW}当前备份文件数量：${FILE_CUR_NUM}，未超过保留数量 ${KEEP_NUM}，无需清理${CEND}"
    fi
}

# 设置定时任务函数
setup_cron() {
    LOGBAK_TASK="/bin/bash /usr/local/bin/logbak > /dev/null 2>&1"
    CRONTAB_BAK_FILE="/tmp/crontab_bak"

    echo -e "${CYELLOW}开始设置定时日志备份，目前为【${INTERVAL}】小时备份一次日志！备份到 ${LOGBAK_DIR} 目录下${CEND}"

    crontab -l >${CRONTAB_BAK_FILE} 2>/dev/null
    sed -i "/\/bin\/bash \/usr\/local\/bin\/logbak *./d" ${CRONTAB_BAK_FILE}
    echo "0 */${INTERVAL} * * * ${LOGBAK_TASK}" >>${CRONTAB_BAK_FILE}
    crontab ${CRONTAB_BAK_FILE} && rm -rf ${CRONTAB_BAK_FILE}

    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}设置定时日志备份成功.【${INTERVAL}】小时备份一次日志！备份到 ${LOGBAK_DIR}${CEND}"
        return 0
    else
        echo -e "${CRED}设置定时任务失败！${CEND}"
        return 1
    fi
}

# 主逻辑
if [ "$1" == "cron" ] || [ "$1" == "setup" ]; then
    setup_cron
    if [ $? -eq 0 ]; then
        echo -e "${CYELLOW}定时日志备份已启动，如果未生效，请重启 crond 服务或者直接重启一下服务器！${CEND}"
        [ "${OS}" == "Debian" ] || [ "${OS}" == "Ubuntu" ] && service cron restart 2>/dev/null || true
        [ "${OS}" == "CentOS" ] || [ "${OS}" == "CentOSStream" ] && systemctl restart crond 2>/dev/null || true
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart crond 2>/dev/null || systemctl restart cron 2>/dev/null || true
        fi
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}设置定时任务失败！${CEND}"
        exit 1
    fi
else
    backup_logs
    cleanup_old_backups

    if [ $? -eq 0 ]; then
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}日志备份失败！${CEND}"
        exit 1
    fi
fi
