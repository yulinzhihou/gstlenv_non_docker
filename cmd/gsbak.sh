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

# comment: 定时数据备份
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

# 获取数据
if [ $# -eq 0 ]; then
    TIME=1
else
    case $1 in
    [1-9] | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23)
        TIME=$1
        ;;
    *)
        TIME=1
        ;;
    esac
fi

# 数据库备份 (原生: 只备份数据库)
SQL_TASK="/bin/bash /usr/local/bin/backup 2 > /dev/null 2>&1 &"
# 版本备份 (原生: 只备份版本)
VERSION_TASK="/bin/bash /usr/local/bin/backup 1 > /dev/null 2>&1 &"
# 定时清理
CRON_DEL_TASK="/bin/bash /usr/local/bin/delbak > /dev/null 2>&1 &"
# 定时任务临时备份文件
CRONTAB_BAK_FILE="/tmp/crontab_bak"

# 定时备份
cron_data_back() {
    echo "${CYELLOW}开始设置定时数据备份，目前为【${TIME}】小时备份一次数据库和版本！备份到 ${BACKUP_DIR:-/tlgame/backup} 目录下${CEND}"
    crontab -l >${CRONTAB_BAK_FILE} 2>/dev/null
    # 删除掉存在的任务
    sed -i "/\/bin\/bash \/usr\/local\/bin\/backup *./d" ${CRONTAB_BAK_FILE}
    sed -i "/\/bin\/bash \/usr\/local\/bin\/delbak *./d" ${CRONTAB_BAK_FILE}
    echo "0 */${TIME} * * * ${SQL_TASK}" >>${CRONTAB_BAK_FILE}
    echo "0 */${TIME} * * * ${VERSION_TASK}" >>${CRONTAB_BAK_FILE}
    echo "0 */${TIME} * * * ${CRON_DEL_TASK}" >>${CRONTAB_BAK_FILE}
    crontab ${CRONTAB_BAK_FILE} && rm -rf ${CRONTAB_BAK_FILE}
    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}设置定时备份成功.【${TIME}】小时备份一次数据库和版本！备份到 ${BACKUP_DIR:-/tlgame/backup} ${CEND}"
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}备份命令不完整，请更新命令[upcmd]后再执行！${CEND}"
    fi
}

# 部署备份脚本
cron_data_back

if [ $? -eq 0 ]; then
    echo -e "${CYELLOW}定时备份已启动，如果未生效，请重启 crond 服务或者直接重启一下服务器！${CEND}"
    [ "${OS}" == "Debian" ] || [ "${OS}" == "Ubuntu" ] && service cron restart 2>/dev/null || true
    [ "${OS}" == "CentOS" ] || [ "${OS}" == "CentOSStream" ] && systemctl restart crond 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart crond 2>/dev/null || systemctl restart cron 2>/dev/null || true
    fi
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}备份命令不完整，请更新命令[upcmd]后再执行！${CEND}"
    exit 1
fi
