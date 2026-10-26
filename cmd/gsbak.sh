#!/bin/bash
# ============================================================
# gsbak - 定时数据备份 (参考 gstlenv gsbak.sh, 原生版)
# 用法: gsbak [1-23]   默认 1 小时备份一次数据库和版本
# 备份到: ${TLBB_HOME}/backup 目录
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
BACKUP_DIR="${TLBB_HOME}/backup"
mkdir -p "$BACKUP_DIR"

# 备份间隔 (小时)
if [ $# -eq 0 ]; then
    TIME=1
else
    case "$1" in
        [1-9]|1[0-9]|2[0-3]) TIME="$1";;
        *) TIME=1;;
    esac
fi

# 数据库备份任务 (本机 mysqldump)
DB_BAK_CMD="/bin/bash /usr/local/bin/backup >/dev/null 2>&1 &"
# 定时清理
DEL_BAK_CMD="/bin/bash /usr/local/bin/delbak >/dev/null 2>&1 &"
CRONTAB_BAK_FILE="/tmp/crontab_bak"

# 环境检查
[ -d "$TLBB_HOME/tlbb" ] || mysqladmin ping >/dev/null 2>&1 || {
    echo "${CRED}环境尚未安装, 请先执行 gstl 或 install.sh 安装环境${CEND}"
    exit 1
}

echo "${CYELLOW}开始设置定时数据备份, 目前为【${TIME}】小时备份一次数据库和版本! 备份到 ${BACKUP_DIR} 目录${CEND}"
crontab -l >"$CRONTAB_BAK_FILE" 2>/dev/null
# 删除旧的同类任务
sed -i '/\/usr\/local\/bin\/backup .*\/d' "$CRONTAB_BAK_FILE"
sed -i '/\/usr\/local\/bin\/delbak .*\/d' "$CRONTAB_BAK_FILE"
echo "0 */${TIME} * * * ${DB_BAK_CMD}" >>"$CRONTAB_BAK_FILE"
echo "0 */${TIME} * * * ${DEL_BAK_CMD}" >>"$CRONTAB_BAK_FILE"
if crontab "$CRONTAB_BAK_FILE" 2>/dev/null; then
    rm -f "$CRONTAB_BAK_FILE"
    echo "${CSUCCESS}设置定时备份成功. 【${TIME}】小时备份一次数据库和版本! 备份到 ${BACKUP_DIR}${CEND}"
    # 重启 crond/cron 使任务生效
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart crond 2>/dev/null || systemctl restart cron 2>/dev/null || true
    else
        service crond restart 2>/dev/null || service cron restart 2>/dev/null || true
    fi
    echo "${CYELLOW}定时备份已启动, 如果未生效, 请重启 crond/cron 服务或者直接重启服务器!${CEND}"
    exit 0
else
    rm -f "$CRONTAB_BAK_FILE"
    echo "${CRED}设置定时备份失败, 请检查 crontab 服务!${CEND}"
    exit 1
fi
