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

# comment: 一键重构环境 (原生: 备份 -> 停服 -> 重置数据库 -> 还原 -> 写入配置)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_HOME="${TLBB_HOME:-/tlgame}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
BACKUP_DIR="${BACKUP_DIR:-/tlgame/backup}"
TL_MYSQL_PASSWORD="${TL_MYSQL_PASSWORD:-123456}"

backup_all() {
    echo -e "${CYELLOW}正在备份版本与数据库，请稍候……${CEND}"
    if [ -d ${TLBB_PATH} ]; then
        cd ${TLBB_HOME} && tar zcf tlbb-rebuild-backup.tar.gz tlbb 2>/dev/null &&
            mv /tlgame/tlbb-rebuild-backup.tar.gz /root/ 2>/dev/null
    fi
    if mysqladmin ping >/dev/null 2>&1; then
        mysqldump -uroot -p"${TL_MYSQL_PASSWORD}" web >/root/web-rebuild-backup.sql 2>/dev/null
        mysqldump -uroot -p"${TL_MYSQL_PASSWORD}" --opt -R tlbbdb >/root/tlbbdb-rebuild-backup.sql 2>/dev/null
    fi
}

restore_all() {
    if [ -f /root/tlbb-rebuild-backup.tar.gz ]; then
        cd /root && tar zxf tlbb-rebuild-backup.tar.gz -C ${TLBB_HOME} && mv /root/tlbb-rebuild-backup.tar.gz ${BACKUP_DIR}/ 2>/dev/null
    fi
    [ -f /root/web-rebuild-backup.sql ] && mysql -uroot -p"${TL_MYSQL_PASSWORD}" web </root/web-rebuild-backup.sql 2>/dev/null
    [ -f /root/tlbbdb-rebuild-backup.sql ] && mysql -uroot -p"${TL_MYSQL_PASSWORD}" tlbbdb </root/tlbbdb-rebuild-backup.sql 2>/dev/null
    rm -f /root/web-rebuild-backup.sql /root/tlbbdb-rebuild-backup.sql 2>/dev/null
}

main() {
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r在准备正行重构环境操作！！，剩余 ${CRED}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
        sleep 1
    done
    echo
    while :; do
        echo -e "${CYELLOW}请输入 [y/n] 是否确认重构环境, 默认[y]确认${CEND}"
        read -e -p "${CYELLOW}请输入确认信息 [y/n]:${CEND} " IS_MODIFY
        IS_MODIFY=${IS_MODIFY:-'y'}
        if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
            echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
        else
            . /root/.gs/.env
            if [ "${IS_MODIFY}" == 'y' ]; then
                echo -e "${CYELLOW}正在重构环境，请稍候……${CEND}"
                # 备份数据
                backup_all
                # 关闭服务端
                close >/dev/null 2>&1
                # 重置数据库 (重新导入初始 SQL)
                reset >/dev/null 2>&1 || true
                # 还原备份
                restore_all
                # 写入配置
                if [ -d ${TLBB_PATH}/Server/Config ]; then
                    setini >/dev/null 2>&1
                fi
            else
                echo -e "${CYELLOW}你已经取消本次操作${CEND}"
            fi
            break
        fi
    done

    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}环境已经重构成功，请稍后重新启动游戏服务器！如果需要启动游戏服务器，请执行【runtlbb】进行开服操作！！如需要配置在线GM，请执行【upgm】进行配置，再执行【runtlbb】进行开服操作！！${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}环境重构失败，请重装系统或者重新安装环境！${CEND}"
        exit 1
    fi
}

main
