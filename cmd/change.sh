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

# comment: 一键换版本脚本, 解压新端/重置数据库/写入配置/启动服务端
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_HOME="${TLBB_HOME:-/tlgame}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
BACKUP_DIR="${BACKUP_DIR:-/tlgame/backup}"
TL_MYSQL_PASSWORD="${TL_MYSQL_PASSWORD:-123456}"

# 备份版本+数据库 (原生)
backup_all() {
    echo -e "${CYELLOW}正在备份版本与数据库，请稍候……${CEND}"
    if [ -d ${TLBB_PATH} ]; then
        cd ${TLBB_HOME} && tar zcf tlbb-change-backup.tar.gz tlbb 2>/dev/null &&
            mv /tlgame/tlbb-change-backup.tar.gz /root/ 2>/dev/null
    fi
    if mysqladmin ping >/dev/null 2>&1; then
        mysqldump -uroot -p"${TL_MYSQL_PASSWORD}" web >/root/web-change-backup.sql 2>/dev/null
        mysqldump -uroot -p"${TL_MYSQL_PASSWORD}" --opt -R tlbbdb >/root/tlbbdb-change-backup.sql 2>/dev/null
    fi
}

# 还原备份
restore_all() {
    if [ -f /root/tlbb-change-backup.tar.gz ]; then
        cd /root && tar zxf tlbb-change-backup.tar.gz -C ${TLBB_HOME} && mv /root/tlbb-change-backup.tar.gz ${BACKUP_DIR}/ 2>/dev/null
    fi
    [ -f /root/web-change-backup.sql ] && mysql -uroot -p"${TL_MYSQL_PASSWORD}" web </root/web-change-backup.sql 2>/dev/null
    [ -f /root/tlbbdb-change-backup.sql ] && mysql -uroot -p"${TL_MYSQL_PASSWORD}" tlbbdb </root/tlbbdb-change-backup.sql 2>/dev/null
    rm -f /root/web-change-backup.sql /root/tlbbdb-change-backup.sql 2>/dev/null
}

# 重置数据库 (重新导入初始 SQL)
reset_db() {
    local SQL_DIR=""
    for d in "${GS_PROJECT}/offline/sql" "${TLBB_PROJECT_DIR}/offline/sql" "/root/.tlgame/offline/sql"; do
        [ -f "$d/tlbbdb.sql" ] && [ -f "$d/web.sql" ] && { SQL_DIR="$d"; break; }
    done
    if [ -z "$SQL_DIR" ]; then
        SQL_DIR=$(find /root /opt /tlgame -type d -name sql -path "*offline*" 2>/dev/null | head -1)
    fi
    if [ -z "$SQL_DIR" ] || [ ! -f "$SQL_DIR/tlbbdb.sql" ] || [ ! -f "$SQL_DIR/web.sql" ]; then
        echo -e "${CRED}未找到初始数据库文件 (offline/sql/tlbbdb.sql, web.sql)${CEND}"
        return 1
    fi
    mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "DROP DATABASE IF EXISTS tlbbdb; DROP DATABASE IF EXISTS web; CREATE DATABASE tlbbdb DEFAULT CHARACTER SET utf8; CREATE DATABASE web DEFAULT CHARACTER SET utf8;" 2>/dev/null
    mysql -uroot -p"${TL_MYSQL_PASSWORD}" web <"$SQL_DIR/web.sql" 2>/dev/null
    mysql -uroot -p"${TL_MYSQL_PASSWORD}" tlbbdb <"$SQL_DIR/tlbbdb.sql" 2>/dev/null
}

main() {
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r在准备正行重构环境，换版本操作！！，剩余 ${CRED}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
        sleep 1
    done
    echo
    while :; do
        echo -e "${CYELLOW}请输入 [y/n] 是否确认重构环境并更换版本, 默认[y]确认${CEND}"
        read -e -p "${CYELLOW}请输入确认信息 [y/n]:${CEND} " IS_MODIFY
        IS_MODIFY=${IS_MODIFY:-'y'}
        if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
            echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
        else
            . /root/.gs/.env
            if [ "${IS_MODIFY}" == 'y' ]; then
                # 备份数据
                backup_all

                if [ ! -d ${TLBB_PATH}/Server/Config ]; then
                    echo -e "${CSUCCESS}未发现版本，请上传版本后依次执行 【 untar 】【 setini 】【 runtlbb 】进行开服！！${CEND}"
                    exit 0
                else
                    echo -e "${CYELLOW}正在重构环境，换版本${CEND}"
                    # 解压新端
                    untar
                    # 重置数据库
                    reset_db
                    # 写入配置
                    setini
                    # 启动服务端
                    runtlbb
                fi
            else
                echo -e "${CYELLOW}你已经取消本次操作${CEND}"
            fi
            break
        fi
    done

    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}换版本成功！！如需重新启动，请执行【 restart 】或者【 runtlbb 】${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}换版本失败！${CEND}"
        exit 1
    fi
}

main
