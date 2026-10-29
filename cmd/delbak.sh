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

# comment: 删除备份文件。默认保留10份 主要是 web.sql tlbbdb.sql tlbb.tar.gz 每个备份文件各10份
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

if [ $# -eq 0 ]; then
    FILE_NUM=10
else
    case $1 in
    [1-9] | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23)
        FILE_NUM=$1
        ;;
    *)
        FILE_NUM=10
        ;;
    esac
fi

# 数据定时清楚，保留个数
cron_data_remove() {
    for FILE in tlbb web tlbbdb; do
        [ ${FILE} == 'tlbb' ] && SUFFIX=tar.gz || SUFFIX=sql
        FILE_CUR_NUM=$(ls -ltr ${BACKUP_DIR:-/tlgame/backup} 2>/dev/null | grep ${FILE}-.*.${SUFFIX} | wc -l)
        if [ ${FILE_CUR_NUM} -gt ${FILE_NUM} ]; then
            let NUM_DEL=${FILE_CUR_NUM}-${FILE_NUM}
            cd ${BACKUP_DIR:-/tlgame/backup} &&
                ls -ltr | grep ${FILE}-.*.${SUFFIX} | awk '{print $9}' | head -n ${NUM_DEL} | xargs rm -rf
        fi
    done
}

# 部署备份脚本
if [ ${FILE_NUM} -ne 0 ]; then
    cron_data_remove
    echo -e "${CSUCCESS}自动清理备份文件完成。${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}备份文件保留数量不能为0${CEND}"
    exit 1
fi
