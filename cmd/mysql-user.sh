#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 设置 MySQL 授权用户/主机/密码 (兼容 MySQL 5.1/5.6/5.7/8.0/8.4, 主机默认 0.0.0.0/0 = 所有机器)

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

# root 密码 (可用环境变量 TL_MYSQL_PASSWORD 覆盖)
ROOT_PW="${TL_MYSQL_PASSWORD:-123456}"

# 参数: mysql-user [用户名] [密码] [授权主机]
# 默认: 用户 gs, 密码 123456, 主机 0.0.0.0/0 (所有机器)
U="${1:-gs}"
P="${2:-123456}"
H="${3:-0.0.0.0/0}"

# 授权主机归一化: 0.0.0.0/0 / 0.0.0.0 / % 均视为所有机器, 对应 MySQL 的 '%'
case "$H" in
    0.0.0.0/0|0.0.0.0|"%") H="%";;
    *) H="$H";;
esac

# 检测 MySQL 版本 (5.7+/8.x 用 CREATE USER IF NOT EXISTS + ALTER USER; 5.6- 用 GRANT ... IDENTIFIED BY)
MV=$(mysql -uroot -p"${ROOT_PW}" -N -e "SELECT VERSION();" 2>/dev/null | head -1)
if [ -z "$MV" ]; then
    echo -e "${CRED}无法连接 MySQL (root/${ROOT_PW}), 请确认数据库已启动且 root 密码正确 (可用 mysql-lock 重置)${CEND}"
    exit 1
fi
MAJ=$(echo "$MV" | cut -d. -f1)
MIN=$(echo "$MV" | cut -d. -f2)
MODE="modern"   # 5.7+/8.x
if [ "$MAJ" = "5" ] && [ "${MIN:-0}" -lt 7 ]; then
    MODE="legacy"  # 5.1/5.5/5.6
fi
echo -e "${CYELLOW}MySQL 版本: ${MV} (${MODE} 模式)${CEND}"

# SQL 单引号转义 (防止密码含 ' 破坏语句)
UQ=$(printf '%s' "$U" | sed "s/'/''/g")
PQ=$(printf '%s' "$P" | sed "s/'/''/g")

if [ "$MODE" = "modern" ]; then
    # 5.7+/8.x: 创建或改密 (优先 mysql_native_password 兼容天龙老端/ODBC 3.51, 失败回退默认插件)
    mysql -uroot -p"${ROOT_PW}" -e "CREATE USER IF NOT EXISTS '${UQ}'@'${H}' IDENTIFIED WITH mysql_native_password BY '${PQ}';" 2>/dev/null || \
    mysql -uroot -p"${ROOT_PW}" -e "CREATE USER IF NOT EXISTS '${UQ}'@'${H}' IDENTIFIED BY '${PQ}';" 2>/dev/null
    mysql -uroot -p"${ROOT_PW}" -e "ALTER USER '${UQ}'@'${H}' IDENTIFIED WITH mysql_native_password BY '${PQ}';" 2>/dev/null || \
    mysql -uroot -p"${ROOT_PW}" -e "ALTER USER '${UQ}'@'${H}' IDENTIFIED BY '${PQ}';" 2>/dev/null
    mysql -uroot -p"${ROOT_PW}" -e "GRANT ALL PRIVILEGES ON *.* TO '${UQ}'@'${H}' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null
else
    # 5.1/5.5/5.6: GRANT ... IDENTIFIED BY 创建并授权, 已存在则 SET PASSWORD 改密
    mysql -uroot -p"${ROOT_PW}" -e "GRANT ALL PRIVILEGES ON *.* TO '${UQ}'@'${H}' IDENTIFIED BY '${PQ}' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null
    mysql -uroot -p"${ROOT_PW}" -e "SET PASSWORD FOR '${UQ}'@'${H}' = PASSWORD('${PQ}'); FLUSH PRIVILEGES;" 2>/dev/null
fi

# 验证并输出结果
if mysql -uroot -p"${ROOT_PW}" -e "SELECT User,Host FROM mysql.user WHERE User='${UQ}' AND Host='${H}';" 2>/dev/null | grep -q "$U"; then
    echo -e "${CSUCCESS}授权成功: ${CYELLOW}${U}${CEND} 密码: ${CYELLOW}${P}${CEND} 主机: ${CYELLOW}${H}${CEND} (ALL PRIVILEGES ON *.* WITH GRANT OPTION)${CEND}"
    [ "$H" = "%" ] && echo -e "${CYELLOW}提示: 主机 ${H} 表示所有机器均可连接 (本地+远程)${CEND}"
    echo -e "${CYELLOW}验证: mysql -u${U} -p${P} -h <服务器IP> -P ${TL_MYSQL_PORT:-3306}${CEND}"
    exit 0
else
    echo -e "${CRED}授权失败, 请检查 MySQL 是否运行 / root 密码是否正确${CEND}"
    exit 1
fi
