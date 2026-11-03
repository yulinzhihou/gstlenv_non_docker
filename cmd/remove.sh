#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 移除整个环境，彻底卸载所有组件 (原生: 备份库SQL到/root → 停服/移除命令/卸载软件/删除配置/迁移数据目录)

# 设置字符编码，确保中文正常显示
{
    export LANG=C.UTF-8 2>/dev/null || export LANG=en_US.UTF-8 2>/dev/null || export LANG=POSIX 2>/dev/null || true
    export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX 2>/dev/null || true
} 2>/dev/null
# 引入全局参数
[ -f /root/.gs/.env ] && . /root/.gs/.env
# 颜色代码
[ -f /usr/local/bin/color ] && . /usr/local/bin/color

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

# 备份 MySQL 数据库 SQL + 版本信息到 /root (remove 第一步, 卸载 MySQL 前执行)
# 备份 web/tlbbdb/tlbbdb_10/tlbbdb_11/tlbbdb_12/tlbbdb_main (仅备份实际存在的库,
# 兼容 2库/3库/自定义结构), 输出 /root/tlbbdb_backup_<时间戳>/ 及同名 .tar.gz
backup_sql() {
    echo -e "${CYELLOW}  → 备份 MySQL 数据库到 /root ...${CEND}"
    local dbpass="${TL_MYSQL_PASSWORD:-${TLBB_DB_PASS:?环境配置缺少数据库密码}}"
    local bkdir="/root/tlbbdb_backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$bkdir" 2>/dev/null || { echo -e "${CWARNING}    无法创建备份目录 $bkdir, 跳过 SQL 备份${CEND}"; return 0; }

    # 确保 MySQL 运行中 (卸载前先备份)
    if ! mysqladmin ping >/dev/null 2>&1; then
        systemctl start mysqld >/dev/null 2>&1 || systemctl start mysql >/dev/null 2>&1 || true
        sleep 3
    fi
    if ! mysqladmin ping >/dev/null 2>&1; then
        echo -e "${CWARNING}    MySQL 未运行, 跳过 SQL 备份 (数据目录仍会由卸载流程自动备份为 .removed 后缀)${CEND}"
        rmdir "$bkdir" 2>/dev/null || true
        return 0
    fi

    # 登录方式: 优先 .env 密码, 失败回退 root 无密登录
    local mauth=(-uroot -p"$dbpass")
    mysql "${mauth[@]}" -e "SELECT 1" >/dev/null 2>&1 || mauth=(-uroot)

    # 逐库备份 (仅备份实际存在的库)
    local dbs=(web tlbbdb tlbbdb_10 tlbbdb_11 tlbbdb_12 tlbbdb_main)
    local n=0 db
    for db in "${dbs[@]}"; do
        if mysql "${mauth[@]}" -N -e "SHOW DATABASES LIKE '${db}'" 2>/dev/null | grep -q "^${db}$"; then
            mysqldump "${mauth[@]}" --databases "$db" --single-transaction --quick --routines > "${bkdir}/${db}.sql" 2>/dev/null \
                && { echo -e "${CGREEN}    ${db} 已备份: ${bkdir}/${db}.sql${CEND}"; n=$((n + 1)); } \
                || echo -e "${CWARNING}    ${db} 备份失败 (已跳过)${CEND}"
        fi
    done
    [ "$n" -eq 0 ] && { echo -e "${CWARNING}    没有可备份的业务数据库 (MySQL 为空或仅系统库)${CEND}"; rm -rf "$bkdir" 2>/dev/null || true; return 0; }

    # 版本信息 (MySQL 版本 + 环境版本参数), 便于恢复时匹配对应档位
    local mver=""
    mver=$(mysql "${mauth[@]}" -N -e "SELECT VERSION()" 2>/dev/null | head -1)
    cat > "${bkdir}/version.txt" <<EOF
# TLBB 环境数据库备份信息 (由 remove 命令卸载前自动生成)
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
MySQL 版本: ${mver}
TLBB_MYSQL_VERSION: ${TLBB_MYSQL_VERSION:-unknown}
备份目录: ${bkdir}
数据库列表: web tlbbdb tlbbdb_10 tlbbdb_11 tlbbdb_12 tlbbdb_main (仅实际存在的库)
恢复方式: mysql -uroot -p<密码> < ${bkdir}/<库名>.sql
EOF

    # 打包到 /root (保留源目录以便单独恢复)
    local tarball="${bkdir}.tar.gz"
    tar czf "$tarball" -C /root "$(basename "$bkdir")" 2>/dev/null \
        && echo -e "${CGREEN}    已打包: ${tarball}${CEND}" \
        || echo -e "${CWARNING}    打包失败 (SQL 目录仍保留在 ${bkdir})${CEND}"
    echo -e "${CSUCCESS}    共备份 ${n} 个数据库到 /root (SQL + 版本信息)${CEND}"
}

main() {
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r在准备正行移除环境操作！！，剩余 ${CRED}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
        sleep 1
    done
    echo
    while :; do
        echo -e "${CYELLOW}请输入 [y/n] 是否确认移除环境, 默认[n]取消${CEND}"
        echo -e "${CYELLOW}提示: 卸载前将先把 web/tlbbdb/tlbbdb_10/tlbbdb_11/tlbbdb_12/tlbbdb_main 数据库备份为 SQL 到 /root, 然后彻底卸载 MySQL/Redis/ODBC 及所有全局命令, 数据目录自动备份${CEND}"
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

                # 2. 备份数据库 SQL + 版本信息到 /root (卸载 MySQL 前执行)
                backup_sql

                # 3. 卸载软件组件
                uninstall_mysql
                uninstall_redis
                uninstall_odbc

                # 4. 移除全局命令
                uninstall_commands

                # 5. 删除环境配置目录
                echo -e "${CYELLOW}  → 删除环境配置 ...${CEND}"
                rm -rf /root/.gs 2>/dev/null || true

                # 6. 迁移数据目录 (保留数据, 可手动恢复)
                echo -e "${CYELLOW}  → 备份服务端数据目录 ...${CEND}"
                if [ -d ${TLBB_HOME} ]; then
                    mv ${TLBB_HOME} ${TLBB_HOME}-$(date +%Y%m%d%H%I%S) 2>/dev/null || true
                    echo -e "${CGREEN}    数据目录已备份为 ${TLBB_HOME}-*${CEND}"
                fi

                # 7. 移除 crontab 中的备份任务
                echo -e "${CYELLOW}  → 清理定时任务 ...${CEND}"
                crontab -l 2>/dev/null | grep -v "/usr/local/bin/backup" | grep -v "/usr/local/bin/delbak" | grep -v "/usr/local/bin/logbak" | crontab - 2>/dev/null || true

                # 8. 删除环境安装目录
                rm -rf /root/.tlgame 2>/dev/null || true

                echo ""
                echo -e "${CSUCCESS}========================================${CEND}"
                echo -e "${CSUCCESS}  环境彻底移除完成!${CEND}"
                echo -e "${CSUCCESS}  已卸载: MySQL / Redis / ODBC / 全局命令${CEND}"
                echo -e "${CSUCCESS}  数据库 SQL 已备份至 /root/tlbbdb_backup_* (含版本信息)${CEND}"
                echo -e "${CSUCCESS}  数据已自动备份为 .removed / -时间戳 后缀${CEND}"
                echo ""
                echo -e "${CYELLOW}  如需重新安装环境, 请重新输入以下命令一键安装 (对齐 gstlenv):${CEND}"
                echo -e "${CSUCCESS}    curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash${CEND}"
                echo -e "${CYELLOW}  离线场景: 将 offline-*.tar.gz / tlbb离线组件*.zip 放到 /root 后执行上述命令 (自动解压并离线安装)${CEND}"
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
