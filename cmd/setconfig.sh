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

# comment: 当用户需要重新生成数据库端口，密码时，则使用此命令进行重装写入配置，注意，执行完成后需要重启服务器再进行配置
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

GS_WHOLE_PATH="${GS_WHOLE_PATH:-/root/.gs/.env}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
BACKUP_DIR="${BACKUP_DIR:-/tlgame/backup}"
TL_MYSQL_PORT="${TL_MYSQL_PORT:-3306}"
# 当前在使用的数据库密码
TL_MYSQL_PASSWORD_CURRENT=${TL_MYSQL_PASSWORD}

# 设置配置参数 (交互提示与 gstlenv 完全一致, 写回 /root/.gs/.env)
setconfig_rebuild() {
    if [ -f ${GS_WHOLE_PATH} ]; then
        echo "${CMAGENTA}如果选择了W机+L机模式，则本服务器不要开启 [billing] 服务！！！${CEND}"
        echo "${CYELLOW}即将设置服务器环境配置荐，请仔细！！注意：W机=Windows服务器，L机=Linux服务器${CEND}"
        echo "${CYELLOW}0=单L机验证，Linux服务器做验证机器，即只需要一台服务器即可${CEND}"
        echo "${CYELLOW}1=W机验证+L机，Windows服务器做验证机器,L机不要开验证服务${CEND}"
        chattr -i ${GS_WHOLE_PATH} 2>/dev/null
        while :; do
            echo
            read -e -p "当前【服务器】选择为${CYELLOW}["${IS_DLQ:-0}"]${CEND}，是否需要修改【1=W机验证+L机，0=单L机验证】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【服务器,1=W机验证+L机，0=单L机验证】(默认: [${IS_DEFAULT_DLQ:-0}]): " IS_NEW_DLQ
                        IS_NEW_DLQ=${IS_NEW_DLQ:-${IS_DEFAULT_DLQ:-0}}
                        case ${IS_NEW_DLQ} in
                        0 | 1)
                            sed -i "s/IS_DLQ=.*/IS_DLQ=${IS_NEW_DLQ}/g" ${GS_WHOLE_PATH}
                            break
                            ;;
                        *)
                            echo "${CWARNING}输入错误! 服务器：1=W机验证+L机，0=单L机${CEND}"
                            break
                            ;;
                        esac
                    done
                else
                    IS_NEW_DLQ=0
                fi
                break
            fi
        done

        # 判断是否输入的是需要登录器。
        if [ ${IS_NEW_DLQ:-0} == '1' ]; then
            while :; do
                echo
                read -e -p "请输入【验证服务器IP地址】(默认: ${BILLING_DEFAULT_SERVER_IPADDR}): " BILLING_NEW_SERVER_IPADDR
                BILLING_NEW_SERVER_IPADDR=${BILLING_NEW_SERVER_IPADDR:-${BILLING_DEFAULT_SERVER_IPADDR}}
                read -e -p "请再次输入【验证服务器IP地址】(默认: ${BILLING_DEFAULT_SERVER_IPADDR}): " BILLING_NEW2_SERVER_IPADDR
                BILLING_NEW2_SERVER_IPADDR=${BILLING_NEW2_SERVER_IPADDR:-${BILLING_DEFAULT_SERVER_IPADDR}}
                # 正则验证是否有效IP
                regex="\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\b"

                [ ${BILLING_NEW_SERVER_IPADDR} = ${BILLING_NEW2_SERVER_IPADDR} ] && ckStep1=0 || ckStep1=1
                ckStep2=$(echo $BILLING_NEW_SERVER_IPADDR | egrep $regex | wc -l)
                ckStep3=$(echo $BILLING_NEW2_SERVER_IPADDR | egrep $regex | wc -l)
                if [[ ${ckStep2} -eq 0 ]] || [[ ${ckStep3} -eq 0 ]]; then
                    echo -e "${CRED}服务器IP地址输入有误，请重新输入${CEND}"
                    exit 1
                fi

                if [[ ${ckStep1} -eq 0 ]]; then
                    sed -i "s/BILLING_SERVER_IPADDR=.*/BILLING_SERVER_IPADDR=${BILLING_NEW_SERVER_IPADDR}/g" ${GS_WHOLE_PATH}
                    break
                else
                    echo -e "${CRED}两次输入的IP不一致，请重新输入${CEND}"
                    exit 1
                fi
            done
        else
            sed -i "s/BILLING_SERVER_IPADDR=.*/BILLING_SERVER_IPADDR=${BILLING_DEFAULT_SERVER_IPADDR}/g" ${GS_WHOLE_PATH}
        fi

        # 配置BILLING_PORT
        while :; do
            echo
            read -e -p "当前【Billing验证端口】为：${CYELLOW}[${BILLING_PORT}]${CEND}，是否需要修改【Billing验证端口】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n' ${CEND}"
                exit 1
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【Billing验证端口】：(默认: ${BILLING_DEFAULT_PORT}): " BILLING_NEW_PORT
                        BILLING_NEW_PORT=${BILLING_NEW_PORT:-${BILLING_DEFAULT_PORT}}
                        if [ ${BILLING_NEW_PORT} == ${BILLING_DEFAULT_PORT} -o ${BILLING_NEW_PORT} -gt 1024 -a ${BILLING_NEW_PORT} -lt 65535 ] >/dev/null 2>&1; then
                            sed -i "s/BILLING_PORT=.*/BILLING_PORT=${BILLING_NEW_PORT}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo "${CWARNING}输入错误! 端口范围: 1025~65534${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改MYSQL_PORT
        while :; do
            echo
            read -e -p "当前【mysql端口】为：${CYELLOW}[${TL_MYSQL_PORT}]${CEND}，是否需要修改【mysql端口】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CRED}输入错误! 请输入 'y' 或者 'n',当前【mysql端口】为：[${TL_MYSQL_PORT}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【mysql端口】：(默认: ${TL_MYSQL_DEFAULT_PORT}): " TL_MYSQL_NEW_PORT
                        TL_MYSQL_NEW_PORT=${TL_MYSQL_NEW_PORT:-${TL_MYSQL_DEFAULT_PORT}}
                        if [ ${TL_MYSQL_NEW_PORT} -eq ${TL_MYSQL_DEFAULT_PORT} -o ${TL_MYSQL_NEW_PORT} -gt 1024 -a ${TL_MYSQL_NEW_PORT} -lt 65535 ] >/dev/null 2>&1; then
                            sed -i "s/TL_MYSQL_PORT=.*/TL_MYSQL_PORT=${TL_MYSQL_NEW_PORT}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo "${CRED}输入错误! 端口范围: 1025~65534${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改登录端口 LOGIN_PORT
        while :; do
            echo
            read -e -p "当前【登录端口】为：${CYELLOW}[${LOGIN_PORT}]${CEND}，是否需要修改【登录端口】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n',当前【登录端口】为：[${LOGIN_PORT}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【登录端口】：(默认: ${LOGIN_DEFAULT_PORT}): " LOGIN_NEW_PORT
                        LOGIN_NEW_PORT=${LOGIN_NEW_PORT:-${LOGIN_DEFAULT_PORT}}
                        if [ ${LOGIN_NEW_PORT} -eq ${LOGIN_DEFAULT_PORT} -o ${LOGIN_NEW_PORT} -gt 1024 -a ${LOGIN_NEW_PORT} -lt 65535 ] >/dev/null 2>&1; then
                            sed -i "s/LOGIN_PORT=.*/LOGIN_PORT=${LOGIN_NEW_PORT}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo "${CRED}输入错误! 端口范围: 1025~65534${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改GAME_PORT
        while :; do
            echo
            read -e -p "当前【游戏端口】为：${CYELLOW}[${SERVER_PORT}]${CEND}，是否需要修改【游戏端口】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n',当前【游戏端口】为：[${SERVER_PORT}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【游戏端口】：(默认: ${SERVER_DEFAULT_PORT}): " SERVER_NEW_PORT
                        SERVER_NEW_PORT=${SERVER_NEW_PORT:-${SERVER_DEFAULT_PORT}}
                        if [ ${SERVER_NEW_PORT} -eq ${SERVER_DEFAULT_PORT} -o ${SERVER_NEW_PORT} -gt 1024 -a ${SERVER_NEW_PORT} -lt 65535 ] >/dev/null 2>&1; then
                            sed -i "s/SERVER_PORT=.*/SERVER_PORT=${SERVER_NEW_PORT}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo -e "${CRED}输入错误! 端口范围: 1025~65534${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改 WEB_PORT
        while :; do
            echo
            read -e -p "当前【网站端口】为：${CYELLOW}[${WEB_PORT}]${CEND}，是否需要修改【网站端口】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n',当前【网站端口】为：[${WEB_PORT}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【网站端口】：(默认: ${WEB_DEFAULT_PORT}): " WEB_NEW_PORT
                        WEB_NEW_PORT=${WEB_NEW_PORT:-${WEB_DEFAULT_PORT}}
                        if [ ${WEB_NEW_PORT} -eq ${WEB_DEFAULT_PORT} -o ${WEB_NEW_PORT} -gt 1 -a ${WEB_NEW_PORT} -lt 65535 ] >/dev/null 2>&1; then
                            sed -i "s/WEB_PORT=.*/WEB_PORT=${WEB_NEW_PORT}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo -e "${CRED}输入错误! 端口范围: 1~65534${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改 WEB_GM_PORT
        while :; do
            echo
            read -e -p "当前【GM网站端口】为：${CYELLOW}[${WEB_GM_PORT}]${CEND}，是否需要修改【GM网站端口】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n',当前【网站端口】为：[${WEB_GM_PORT}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【网站端口】：(默认: ${WEB_GM_DEFAULT_PORT}): " WEB_GM_NEW_PORT
                        WEB_GM_NEW_PORT=${WEB_GM_NEW_PORT:-${WEB_GM_DEFAULT_PORT}}
                        if [ ${WEB_GM_NEW_PORT} -eq ${WEB_GM_DEFAULT_PORT} -o ${WEB_GM_NEW_PORT} -gt 1 -a ${WEB_GM_NEW_PORT} -lt 65535 ] >/dev/null 2>&1; then
                            sed -i "s/WEB_GM_PORT=.*/WEB_GM_PORT=${WEB_GM_NEW_PORT}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo -e "${CRED}输入错误! 端口范围: 1~65534${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改数据库密码
        while :; do
            echo
            read -e -p "当前【数据库密码】为：${CYELLOW}[${TL_MYSQL_PASSWORD}]${CEND}，是否需要修改【数据库密码】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n',当前【数据库密码】为：[${TL_MYSQL_PASSWORD}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【数据库密码】(默认: ${TL_MYSQL_DEFAULT_PASSWORD}): " TL_MYSQL_NEW_PASSWORD
                        TL_MYSQL_NEW_PASSWORD=${TL_MYSQL_NEW_PASSWORD:-${TL_MYSQL_DEFAULT_PASSWORD}}
                        if ((${#TL_MYSQL_NEW_PASSWORD} >= 5)); then
                            sed -i "s/TL_MYSQL_PASSWORD=.*/TL_MYSQL_PASSWORD=${TL_MYSQL_NEW_PASSWORD}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo "${CRED}密码最少要6个字符! ${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done

        # 修改Redis密码 (原生: 供 GM 工具/后续使用, 本机未装 Redis 时仅保存配置)
        while :; do
            echo
            read -e -p "当前【Redis密码】为：${CYELLOW}[${REDIS_PASSWORD}]${CEND}，是否需要修改【Redis密码】 [y/n](默认: n): " IS_MODIFY
            IS_MODIFY=${IS_MODIFY:-'n'}
            if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
                echo "${CWARNING}输入错误! 请输入 'y' 或者 'n',当前【Redis密码】为：[${REDIS_PASSWORD}]${CEND}"
            else
                if [ "${IS_MODIFY}" == 'y' ]; then
                    while :; do
                        echo
                        read -e -p "请输入【Redis密码】(默认: ${REDIS_DEFAULT_PASSWORD}): " REDIS_NEW_PASSWORD
                        REDIS_NEW_PASSWORD=${REDIS_NEW_PASSWORD:-${REDIS_DEFAULT_PASSWORD}}
                        if ((${#REDIS_NEW_PASSWORD} >= 1)); then
                            sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=${REDIS_NEW_PASSWORD}/g" ${GS_WHOLE_PATH}
                            break
                        else
                            echo "${CRED}密码不能为空! ${CEND}"
                            exit 1
                        fi
                    done
                fi
                break
            fi
        done
        echo "${CYELLOW}请稍等，正在写入配置信息……${CEND}"
        chattr +i ${GS_WHOLE_PATH} 2>/dev/null
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "GS专用环境还没初始化，请先执行【 gstl 】或重新安装环境！"
        exit 1
    fi
    # 原生: 无需重启容器, 配置写入 /root/.gs/.env 即生效 (配合 setini 重新写服务端配置)
}

# 备份数据 (原生: tar 版本 + mysqldump)
setconfig_backup() {
    echo -ne "正在备份版本数据请稍候……\r\n"
    cd ${TLBB_HOME:-/tlgame} && tar zcf tlbb-setconfig-backup.tar.gz tlbb 2>/dev/null &&
        mv /tlgame/tlbb-setconfig-backup.tar.gz /root/ 2>/dev/null
    mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -e "show databases;" >/dev/null 2>&1 || {
        echo "${CRED}数据库密码错误或数据库未运行, 无法备份数据库!${CEND}"
        return 1
    }
    mysqldump -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" web >/root/web-setconfig-backup.sql 2>/dev/null && echo "  web 库已备份"
    mysqldump -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" --opt -R tlbbdb >/root/tlbbdb-setconfig-backup.sql 2>/dev/null && echo "  tlbbdb 库已备份"
}

# 还原数据
setconfig_restore() {
    echo -ne "正在还原修改参数之前的数据库与版本请稍候……\r\n"
    if [ -f "/root/tlbb-setconfig-backup.tar.gz" ]; then
        cd /root && tar zxf tlbb-setconfig-backup.tar.gz -C ${TLBB_HOME:-/tlgame} && mv /root/tlbb-setconfig-backup.tar.gz ${BACKUP_DIR}/ 2>/dev/null
    fi
    [ -f /root/web-setconfig-backup.sql ] && mysql -uroot -p"${TL_MYSQL_PASSWORD}" web </root/web-setconfig-backup.sql 2>/dev/null
    [ -f /root/tlbbdb-setconfig-backup.sql ] && mysql -uroot -p"${TL_MYSQL_PASSWORD}" tlbbdb </root/tlbbdb-setconfig-backup.sql 2>/dev/null
    rm -f /root/web-setconfig-backup.sql /root/tlbbdb-setconfig-backup.sql 2>/dev/null
}

# 修改数据库密码 (兼容 MySQL 5.1/5.7/8.0)
change_password() {
    . /root/.gs/.env
    if ! mysqladmin ping >/dev/null 2>&1; then
        echo -e "${CRED}数据库未运行, 无法修改密码!${CEND}"
        return 1
    fi
    local mver
    mver=$(mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -N -e "SELECT VERSION();" 2>/dev/null | head -1)
    case "$mver" in
        8.* | 5.7*)
            # 新版本 (5.7/8.0): ALTER USER
            mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -e \
                "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${TL_MYSQL_PASSWORD}'; ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${TL_MYSQL_PASSWORD}'; FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
            ;;
        *)
            # 老版本 (5.1/5.5/5.6): SET PASSWORD (分句执行, 容忍 root@% 不存在)
            mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -e \
                "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${TL_MYSQL_PASSWORD}'); FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
            mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -e \
                "SET PASSWORD FOR 'root'@'%' = PASSWORD('${TL_MYSQL_PASSWORD}'); FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
            ;;
    esac
    # 验证新密码
    if mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${CSUCCESS}数据库密码修改成功！新密码已生效。${CEND}"
        return 0
    else
        echo -e "${CRED}数据库密码修改失败，请检查数据库状态与旧密码。${CEND}"
        return 1
    fi
}

# 核心调用
main() {
    for ((time = 3; time >= 0; time--)); do
        echo -ne "\r在准备正行重新生成配置文件操作！！，剩余 ${CRED}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
        sleep 1
    done
    #
    while :; do
        echo
        echo -e "${CYELLOW}请选择是否需要保留原来的版本与数据库${CEND}"
        echo -e "${CYELLOW}如果是刚刚搭建环境成功，则不需要保留原来版本和数据。请选择[n]${CEND}"
        read -e -p "${CYELLOW}保留请输入[y],不保留请输入[n],默认是保留[y]:${CEND} " IS_MODIFY
        IS_MODIFY=${IS_MODIFY:-'y'}
        if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
            echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
        else
            . /root/.gs/.env
            if [ "${IS_MODIFY}" == 'y' ]; then
                # 备份数据
                setconfig_backup

                if [ ! -d ${TLBB_PATH}/Server/Config ]; then
                    echo -e "${CSUCCESS}未发现版本，请上传版本后依次执行 【 untar 】【 setini 】【 runtlbb 】进行开服！！${CEND}"
                    exit 0
                else
                    setini
                fi
            fi
            # 设置参数
            setconfig_rebuild
            # 修改数据库密码 (使用旧密码 ALTER 到新密码)
            change_password
            # 重新写入服务端配置 (原生: 无需重启容器, 重新执行 setini)
            if [ -d ${TLBB_PATH}/Server/Config ]; then
                setini >/dev/null 2>&1
            fi
            # 还原数据 (此时已使用新密码)
            setconfig_restore
            break
        fi
    done

    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}配置写入成功！！,可以使用 【 curgs 】命令查看配置的信息${CEND}"
        echo -e "${CYELLOW}重要: 修改端口/密码后, 请执行【restart】重启服务端, 并使用【setini】重新写入服务端配置${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}配置写入失败，请移除环境重新安装！！${CEND}"
        exit 1
    fi
}

main
