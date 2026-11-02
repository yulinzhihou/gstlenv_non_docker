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

# comment: 移除整个环境，彻底卸载所有组件 (原生: 停服/移除命令/卸载软件/删除配置/迁移数据目录)
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

TLBB_HOME="${TLBB_HOME:-/tlgame}"
GS_WHOLE_PATH="${GS_WHOLE_PATH:-/root/.gs/.env}"
GS_PROJECT="${GS_PROJECT:-/root/.tlgame}"

# 检测包管理器
detect_pkg_mgr() {
    if command -v dnf >/dev/null 2>&1; then echo "dnf";
    elif command -v yum >/dev/null 2>&1; then echo "yum";
    elif command -v apt-get >/dev/null 2>&1; then echo "apt";
    else echo "none"; fi
}

# 停止并卸载 MySQL
uninstall_mysql() {
    echo -e "${CYELLOW}  → 停止并卸载 MySQL ...${CEND}"
    # 停止服务
    systemctl stop mysqld 2>/dev/null || systemctl stop mysql 2>/dev/null || true
    systemctl disable mysqld 2>/dev/null || systemctl disable mysql 2>/dev/null || true
    pkill -9 mysqld 2>/dev/null || true

    local mgr; mgr=$(detect_pkg_mgr)
    if [ "$mgr" = "dnf" ] || [ "$mgr" = "yum" ]; then
        # 卸载 MySQL 相关包 (官方版 + 系统自带版)
        $mgr remove -y mysql-community-server mysql-community-client mysql-community-libs mysql-community-common \
            mysql-server mysql mysql-libs 2>/dev/null || true
    elif [ "$mgr" = "apt" ]; then
        apt-get remove -y --purge mysql-server mysql-client mysql-common 2>/dev/null || true
    fi

    # 删除数据目录和配置 (保留备份)
    local bak_suffix=$(date +%Y%m%d%H%I%S)
    [ -d /var/lib/mysql ] && mv /var/lib/mysql /var/lib/mysql.removed.$bak_suffix 2>/dev/null || true
    [ -d /etc/my.cnf.d ] && mv /etc/my.cnf.d /etc/my.cnf.d.removed.$bak_suffix 2>/dev/null || true
    [ -f /etc/my.cnf ] && mv /etc/my.cnf /etc/my.cnf.removed.$bak_suffix 2>/dev/null || true
    [ -f /etc/yum.repos.d/mysql-community.repo ] && rm -f /etc/yum.repos.d/mysql-community.repo 2>/dev/null || true

    echo -e "${CGREEN}    MySQL 卸载完成 (数据已备份为 .removed.$bak_suffix)${CEND}"
}

# 停止并卸载 Redis
uninstall_redis() {
    echo -e "${CYELLOW}  → 停止并卸载 Redis ...${CEND}"
    # 停止服务
    systemctl stop redis 2>/dev/null || systemctl stop redis-server 2>/dev/null || true
    systemctl disable redis 2>/dev/null || systemctl disable redis-server 2>/dev/null || true
    pkill -9 redis-server 2>/dev/null || true

    local mgr; mgr=$(detect_pkg_mgr)
    if [ "$mgr" = "dnf" ] || [ "$mgr" = "yum" ]; then
        $mgr remove -y redis 2>/dev/null || true
    elif [ "$mgr" = "apt" ]; then
        apt-get remove -y --purge redis-server 2>/dev/null || true
    fi

    # 删除配置
    [ -f /etc/redis.conf ] && mv /etc/redis.conf /etc/redis.conf.removed 2>/dev/null || true
    [ -d /etc/redis ] && mv /etc/redis /etc/redis.removed 2>/dev/null || true

    echo -e "${CGREEN}    Redis 卸载完成${CEND}"
}

# 卸载 ODBC 相关配置
uninstall_odbc() {
    echo -e "${CYELLOW}  → 清理 ODBC 配置 ...${CEND}"
    [ -f /etc/odbc.ini ] && rm -f /etc/odbc.ini 2>/dev/null || true
    [ -f /etc/odbcinst.ini ] && rm -f /etc/odbcinst.ini 2>/dev/null || true
    echo -e "${CGREEN}    ODBC 配置已清理${CEND}"
}

# 卸载全局命令
uninstall_commands() {
    echo -e "${CYELLOW}  → 移除全局命令 ...${CEND}"
    for name in untar setini runtlbb runtop setconfig setpoint setvalid gslog rmlog link gsfix gsbak swap change close restart remove backup reset restore delbak logbak curgs gs gstl step upcmd upow transfer rebuild gsctl color; do
        rm -f /usr/local/bin/${name} 2>/dev/null
    done
    echo -e "${CGREEN}    全局命令已移除${CEND}"
}

main() {
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r在准备正行移除环境操作！！，剩余 ${CRED}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
        sleep 1
    done
    echo
    while :; do
        echo -e "${CYELLOW}请输入 [y/n] 是否确认移除环境, 默认[n]取消${CEND}"
        echo -e "${CYELLOW}提示: 将彻底卸载 MySQL/Redis/ODBC 及所有全局命令, 数据目录会自动备份${CEND}"
        read -e -p "${CYELLOW}请输入确认信息 [y/n]:${CEND} " IS_MODIFY
        IS_MODIFY=${IS_MODIFY:-'n'}
        if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
            echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
        else
            if [ "${IS_MODIFY}" == 'y' ]; then
                echo -e "${CYELLOW}正在彻底移除环境……${CEND}"
                echo ""

                # 1. 关闭服务端
                echo -e "${CYELLOW}  → 关闭游戏服务端 ...${CEND}"
                close >/dev/null 2>&1 || true

                # 2. 卸载软件组件
                uninstall_mysql
                uninstall_redis
                uninstall_odbc

                # 3. 移除全局命令
                uninstall_commands

                # 4. 删除环境配置目录
                echo -e "${CYELLOW}  → 删除环境配置 ...${CEND}"
                rm -rf /root/.gs 2>/dev/null || true

                # 5. 迁移数据目录 (保留数据, 可手动恢复)
                echo -e "${CYELLOW}  → 备份服务端数据目录 ...${CEND}"
                if [ -d ${TLBB_HOME} ]; then
                    mv ${TLBB_HOME} ${TLBB_HOME}-$(date +%Y%m%d%H%I%S) 2>/dev/null || true
                    echo -e "${CGREEN}    数据目录已备份为 ${TLBB_HOME}-*${CEND}"
                fi

                # 6. 移除 crontab 中的备份任务
                echo -e "${CYELLOW}  → 清理定时任务 ...${CEND}"
                crontab -l 2>/dev/null | grep -v "/usr/local/bin/backup" | grep -v "/usr/local/bin/delbak" | grep -v "/usr/local/bin/logbak" | crontab - 2>/dev/null || true

                # 7. 删除环境安装目录
                rm -rf /root/.tlgame 2>/dev/null || true

                echo ""
                echo -e "${CSUCCESS}========================================${CEND}"
                echo -e "${CSUCCESS}  环境彻底移除完成!${CEND}"
                echo -e "${CSUCCESS}  已卸载: MySQL / Redis / ODBC / 全局命令${CEND}"
                echo -e "${CSUCCESS}  数据已自动备份为 .removed / -时间戳 后缀${CEND}"
                echo -e "${CSUCCESS}  如需重新安装, 请重新下载环境包执行安装${CEND}"
                echo -e "${CSUCCESS}========================================${CEND}"
                exit 0
            else
                echo -e "${CYELLOW}你已经取消本次操作${CEND}"
                exit 0
            fi
            break
        fi
    done
}

main
