#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 锁定 MySQL: 删除所有机器(% 主机)连接账号, 仅保留 root@127.0.0.1 与 root@localhost (兼容 5.1/5.6/5.7/8.0/8.4)

# 设置字符编码，确保中文正常显示
{
    export LANG=C.UTF-8 2>/dev/null || export LANG=en_US.UTF-8 2>/dev/null || export LANG=POSIX 2>/dev/null || true
    export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX 2>/dev/null || true
} 2>/dev/null
# 引入全局参数
[ -f /root/.gs/.env ] && . /root/.gs/.env
# 颜色代码
[ -f /usr/local/bin/color ] && . /usr/local/bin/color

if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

ROOT_PW="${TL_MYSQL_PASSWORD:-123456}"

MV=$(mysql -uroot -p"${ROOT_PW}" -N -e "SELECT VERSION();" 2>/dev/null | head -1)
if [ -z "$MV" ]; then
    echo -e "${CRED}无法连接 MySQL (root/${ROOT_PW}), 请确认数据库已启动且 root 密码正确${CEND}"
    exit 1
fi
MAJ=$(echo "$MV" | cut -d. -f1)
MIN=$(echo "$MV" | cut -d. -f2)
MODE="modern"
if [ "$MAJ" = "5" ] && [ "${MIN:-0}" -lt 7 ]; then
    MODE="legacy"
fi
echo -e "${CYELLOW}MySQL 版本: ${MV} (${MODE} 模式)${CEND}"

while :; do
    echo
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r即将关闭所有机器的数据库连接 (删除所有 % 主机账号)！！剩余 ${CYELLOW}$time${CEND} 秒，可在计时结束前按 CTRL+C 退出\r"
        sleep 1
    done
    echo -ne "\n\r"

    # 1) 删除所有 Host='%' 账号 (所有机器连接), 5.1~8.x 通用
    DELETED=$(mysql -uroot -p"${ROOT_PW}" -N -e "SELECT User FROM mysql.user WHERE Host='%';" 2>/dev/null | grep -v '^$' | sort -u | tr '\n' ' ')
    mysql -uroot -p"${ROOT_PW}" -e "DELETE FROM mysql.user WHERE Host='%'; FLUSH PRIVILEGES;" 2>/dev/null || \
        { echo -e "${CRED}删除 % 主机账号失败${CEND}"; exit 1; }

    # 2) 确保 root@localhost 存在且密码正确
    if [ "$MODE" = "modern" ]; then
        mysql -uroot -p"${ROOT_PW}" -e "CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PW}'; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PW}';" 2>/dev/null || \
        mysql -uroot -p"${ROOT_PW}" -e "CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${ROOT_PW}'; ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PW}';" 2>/dev/null
    else
        mysql -uroot -p"${ROOT_PW}" -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${ROOT_PW}'); FLUSH PRIVILEGES;" 2>/dev/null
    fi
    mysql -uroot -p"${ROOT_PW}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null

    # 3) 确保 root@127.0.0.1 存在且密码正确 (本地回环远程方式也保留)
    if [ "$MODE" = "modern" ]; then
        mysql -uroot -p"${ROOT_PW}" -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${ROOT_PW}'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${ROOT_PW}';" 2>/dev/null || \
        mysql -uroot -p"${ROOT_PW}" -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${ROOT_PW}'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${ROOT_PW}';" 2>/dev/null
    else
        mysql -uroot -p"${ROOT_PW}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY '${ROOT_PW}' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null
    fi
    mysql -uroot -p"${ROOT_PW}" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null

    echo -e "${CSUCCESS}已关闭所有机器连接${CEND}"
    [ -n "$DELETED" ] && echo -e "${CYELLOW}已删除 % 主机账号: ${DELETED}${CEND}" || echo -e "${CYELLOW}原本无 % 主机账号${CEND}"
    echo -e "${CSUCCESS}当前保留账号:${CEND}"
    mysql -uroot -p"${ROOT_PW}" -e "SELECT User,Host FROM mysql.user ORDER BY User,Host;" 2>/dev/null
    echo -e "${CYELLOW}root 密码: ${ROOT_PW}${CEND}"
    echo -e "${CYELLOW}如需开放远程连接, 执行: mysql-user [用户名] [密码] [主机]  (主机默认 0.0.0.0/0 = 所有机器)${CEND}"
    exit 0
done
