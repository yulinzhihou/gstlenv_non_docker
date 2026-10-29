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

# comment: 删档脚本 (原生: drop 库并重新导入初始 SQL)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TL_MYSQL_PASSWORD="${TL_MYSQL_PASSWORD:-123456}"

while :; do
    echo
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r在准备正行删档操作！！，剩余 ${CYELLOW}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！如果需要备份，退出后再执行【backup】命令\r"
        sleep 1
    done
    echo -ne "\n\r"
    echo -ne "${CYELLOW}正在删档，数据全部清空…………\r${CEND}"

    # 原生: 从环境包 offline/sql 重新导入初始库
    SQL_DIR=""
    for d in "${GS_PROJECT}/offline/sql" "${TLBB_PROJECT_DIR}/offline/sql" "/root/.tlgame/offline/sql"; do
        [ -f "$d/tlbbdb.sql" ] && [ -f "$d/web.sql" ] && { SQL_DIR="$d"; break; }
    done
    if [ -z "$SQL_DIR" ]; then
        SQL_DIR=$(find /root /opt /tlgame -type d -name sql -path "*offline*" 2>/dev/null | head -1)
    fi
    if [ -z "$SQL_DIR" ] || [ ! -f "$SQL_DIR/tlbbdb.sql" ] || [ ! -f "$SQL_DIR/web.sql" ]; then
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}未找到初始数据库文件 (offline/sql/tlbbdb.sql, web.sql)，无法删档重置！${CEND}"
        exit 1
    fi

    mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "DROP DATABASE IF EXISTS tlbbdb; DROP DATABASE IF EXISTS web; CREATE DATABASE tlbbdb DEFAULT CHARACTER SET utf8; CREATE DATABASE web DEFAULT CHARACTER SET utf8;" 2>/dev/null
    mysql -uroot -p"${TL_MYSQL_PASSWORD}" web <"$SQL_DIR/web.sql" 2>/dev/null && echo "  web 库已重置"
    mysql -uroot -p"${TL_MYSQL_PASSWORD}" tlbbdb <"$SQL_DIR/tlbbdb.sql" 2>/dev/null && echo "  tlbbdb 库已重置"

    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}已经删档成功${CEND}"
        echo -e "${CYELLOW}删档后请重启服务端生效: 【restart】 或 【runtlbb】${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}已经删档失败！可能需要重装系统或者环境了！${CEND}"
        exit 1
    fi
done
