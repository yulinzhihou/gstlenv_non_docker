#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 根据env文件的环境变量，修改对应的配置文件，复制配置文件替换到指定目录，并给与相应权限

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

BASE_PATH="${GS_PROJECT}/config"
TLBB_HOME="${TLBB_HOME:-/tlgame}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
mkdir -p "${BASE_PATH}"

# 转换为 CRLF 行尾 (对齐 gstlenv unix2dos, TLBB ini 需 Windows 行尾)
to_crlf() {
    local f="$1"
    if command -v unix2dos >/dev/null 2>&1; then
        unix2dos "$f" >/dev/null 2>&1
    else
        sed -i 's/\r\?$/\r/' "$f"
    fi
}

# 配置写入前检查实际目标, 不在缺失文件时继续生成空配置。
if [ ! -d "${TLBB_PATH}/Server/Config" ]; then
    echo -e "${GSISSUE}\r\n"
    printf '%s\n' "${CRED}未找到服务端配置目录: ${TLBB_PATH}/Server/Config${CEND}"
    echo "请先执行更新后的 untar, 确认它输出的服务端目录与 TLBB_PATH 一致。"
    echo "默认读取 /root/tlbb.tar.gz 或 /root/tlbb.zip, 部署到 $TLBB_PATH。"
    exit 1
fi
for ini_file in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
    if [ ! -f "${TLBB_PATH}/Server/Config/$ini_file" ]; then
        printf '%s\n' "${CRED}缺少服务端配置文件: ${TLBB_PATH}/Server/Config/$ini_file${CEND}"
        echo -e "${GSISSUE}\r\n"
        exit 1
    fi
done

if [ ! -d "${TLBB_HOME}/billing/" ]; then
    mkdir -p "${TLBB_HOME}/billing/" &&
        chown -R root:root "${TLBB_HOME}/billing" "${TLBB_PATH}" &&
        chmod -R 777 "${TLBB_HOME}/billing" "${TLBB_PATH}"
fi

# billing 运行目录 (原生: run.sh 中的 /home/billing)
if [ ! -d /home/billing ]; then
    mkdir -p /home/billing
fi
# 如果服务端自带 billing 程序则直接用, 否则提示用户提供
if [ -f /home/billing/billing ]; then
    :
elif [ -f "${TLBB_HOME}/billing/billing" ]; then
    ln -sfn "${TLBB_HOME}/billing" /home/billing
else
    echo -e "${CWARNING}未找到 billing 程序, 请将 billing 程序(billing 可执行文件)放入 /home/billing 目录, 否则登录器验证服务无法启动!${CEND}"
fi
chmod -R 777 /home/billing 2>/dev/null

# 游戏内注册=0，登录器注册=1
if [ ${IS_DLQ:-0} -eq 0 ]; then
    # 每次更新后，先重置更改过的文件: 追加 billing 启动命令到 run.sh
    if [ -f "${TLBB_PATH}/run.sh" ]; then
        cat ${TLBB_PATH}/run.sh | grep "cd /home/billing && ./billing up -d" >/dev/null 2>&1
        if [ $? -eq 1 ]; then
            # 确保文件末尾有换行符，避免命令被直接拼接到上一行
            printf '\n' >>${TLBB_PATH}/run.sh
            echo "" >>${TLBB_PATH}/run.sh
            echo "cd /home/billing && ./billing up -d" >>${TLBB_PATH}/run.sh
            echo "" >>${TLBB_PATH}/run.sh
        fi
    fi
else
    # 登录器注册模式: 本机(L机)不开 billing 验证
    if [ -f "${TLBB_PATH}/run.sh" ]; then
        sed -i "s/GS_BILLING/sleep 0/g" ${TLBB_PATH}/run.sh
    fi
fi

# 三个 ini 文件的替换
MOTHER_IP="0.0.0.0"  # Mother区块的新IP
WORLD_IP="127.0.0.1" # World区块的新IP
IP1="${BILLING_SERVER_IPADDR:-127.0.0.1}"
PORT1="${BILLING_PORT:-21818}"
IP2="127.0.0.1"
PORT2="${SERVER_PORT:-15680}"
IP3="127.0.0.1"
PORT3="${LOGIN_PORT:-13580}"

# 使用 awk 替换 ServerInfo.ini 的 IP0/Port0, IP1/Port1, IP2/Port2 与 [Mother]/[World] IP
# (单次遍历串联处理, 兼容 gawk/mawk)
awk -v ip1="$IP1" -v port1="$PORT1" \
    -v ip2="$IP2" -v port2="$PORT2" \
    -v ip3="$IP3" -v port3="$PORT3" \
    -v mother_ip="$MOTHER_IP" -v world_ip="$WORLD_IP" '
BEGIN {
    ips[0] = ip1; ports[0] = port1
    ips[1] = ip2; ports[1] = port2
    ips[2] = ip3; ports[2] = port3
    ipn = 0; portn = 0
    section = ""
}
/^IP[0-9]=/ {
    if (ipn < 3) { $0 = "IP" ipn "=" ips[ipn] }
    ipn++
}
/^Port[0-9]=/ {
    if (portn < 3) { $0 = "Port" portn "=" ports[portn] }
    portn++
}
/^\[/ {
    section = toupper($0)
    gsub(/[ \t]/, "", section)
    gsub(/[\[\]]/, "", section)
}
/^IP[ \t]*=/ {
    if (section == "MOTHER") { $0 = "IP=" mother_ip; section = "" }
    else if (section == "WORLD") { $0 = "IP=" world_ip; section = "" }
}
{ print }
' "${TLBB_PATH}/Server/Config/ServerInfo.ini" >${BASE_PATH}/tmp1 &&
    to_crlf ${BASE_PATH}/tmp1

# 数据库连接配置 (原生: 本机 MySQL 127.0.0.1)
DBIP_NEW="127.0.0.1"
DBPort_NEW="${TL_MYSQL_PORT:-3306}"
DBName_NEW="tlbbdb"
if [[ "${TLBB_MYSQL_VERSION:-}" = 80 || "${TLBB_MYSQL_VERSION:-}" = 84 ]] && [ "${TLBB_DB_LAYOUT:-3}" = 3 ]; then
    DBName_NEW="tlbbdb_main"
fi
DBUser_NEW="${TLBB_MYSQL_USER:-gs}"
DBPassword_NEW="${TLBB_MYSQL_PASSWORD:-${TL_MYSQL_PASSWORD:?配置文件缺少数据库密码}}"

# LoginInfo.ini [System] 段
awk -v dbip="$DBIP_NEW" -v dbport="$DBPort_NEW" \
    -v dbname="$DBName_NEW" -v dbuser="$DBUser_NEW" \
    -v dbpassword="$DBPassword_NEW" '
/^\[System\]/ { in_system=1 }
/^\[/ && !/\[System\]/ { in_system=0 }
in_system && /^DBIP=/ { $0="DBIP=" dbip }
in_system && /^DBPort=/ { $0="DBPort=" dbport }
in_system && /^DBName=/ { $0="DBName=" dbname }
in_system && /^DBUser=/ { $0="DBUser=" dbuser }
in_system && /^DBPassword=/ { $0="DBPassword=" dbpassword }
{ print }
' "${TLBB_PATH}/Server/Config/LoginInfo.ini" >${BASE_PATH}/tmp2 &&
    to_crlf ${BASE_PATH}/tmp2

# ShareMemInfo.ini [System] 段
awk -v dbip="$DBIP_NEW" -v dbport="$DBPort_NEW" \
    -v dbname="$DBName_NEW" -v dbuser="$DBUser_NEW" \
    -v dbpassword="$DBPassword_NEW" '
/^\[System\]/ { in_system=1 }
/^\[/ && !/\[System\]/ { in_system=0 }
in_system && /^DBIP=/ { $0="DBIP=" dbip }
in_system && /^DBPort=/ { $0="DBPort=" dbport }
in_system && /^DBName=/ { $0="DBName=" dbname }
in_system && /^DBUser=/ { $0="DBUser=" dbuser }
in_system && /^DBPassword=/ { $0="DBPassword=" dbpassword }
{ print }
' "${TLBB_PATH}/Server/Config/ShareMemInfo.ini" >${BASE_PATH}/tmp3 &&
    to_crlf ${BASE_PATH}/tmp3

# 自动探测 ODBC 驱动 (优先级: mysql8 -> mysql5 -> myodbc3)
detect_odbc_driver() {
    local d
    for d in "${TLBB_ODBC_DRIVER:-}" /usr/lib64/libmaodbc.so /usr/lib64/libmyodbc8w.so /usr/lib64/libmyodbc5w.so /usr/lib64/libmyodbc.so /usr/lib/x86_64-linux-gnu/libmaodbc.so /usr/lib/libmyodbc5.so /usr/lib/libmyodbc3.so /usr/lib/i386-linux-gnu/libmyodbc3.so; do
        [ -f "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}
ODBC_DRIVER=$(detect_odbc_driver) || { echo "未找到已安装的 ODBC 驱动, 请先修复环境"; exit 1; }

# 生成 odbc.ini (写入 /etc)
touch /etc/odbc.ini && chmod 600 /etc/odbc.ini || exit 1
cat >/etc/odbc.ini <<EOF
[tlbbdb]
Driver		= ${ODBC_DRIVER}
Description	= MyODBC Driver DSN
SERVER		= ${DBIP_NEW}
PORT		= ${DBPort_NEW}
USER		= ${DBUser_NEW}
Password	= ${DBPassword_NEW}
Database	= ${DBName_NEW}
OPTION		= 3
SOCKET		=

[Default]
Driver		= ${ODBC_DRIVER}
Description	= MyODBC Driver DSN
SERVER	   	= ${DBIP_NEW}
PORT		= ${DBPort_NEW}
USER		= ${DBUser_NEW}
Password	= ${DBPassword_NEW}
Database	= ${DBName_NEW}
OPTION		= 3
SOCKET		=

EOF
if [ "$DBName_NEW" = tlbbdb_main ]; then
    for db in tlbbdb_main tlbbdb_10 CHAR_DBTABASE; do
        target_db=tlbbdb_main
        [ "$db" != tlbbdb_10 ] || target_db=tlbbdb_10
        cat >> /etc/odbc.ini <<EOF
[$db]
Driver = ${ODBC_DRIVER}
SERVER = ${DBIP_NEW}
PORT = ${DBPort_NEW}
USER = ${DBUser_NEW}
Password = ${DBPassword_NEW}
Database = ${target_db}

EOF
    done
fi

# 生成 billing config.yaml (原生: /home/billing, 与 run.sh 中的路径一致)
# bill_type 0经典 1怀旧 (MySQL 8.0/8.4 源端视为怀旧/64位)
BILLING_GAME_SRC=0
if [ "${TLBB_MYSQL_VERSION:-auto}" = "80" ] || [ "${TLBB_MYSQL_VERSION:-auto}" = "84" ]; then
    BILLING_GAME_SRC=1
fi
cat >/home/billing/config.yaml <<EOF
ip: 127.0.0.1
port: ${BILLING_PORT:-21818}
db_host: ${DBIP_NEW}
db_port: ${DBPort_NEW}
db_user: ${DBUser_NEW}
db_password: ${DBPassword_NEW}
db_name: web
allow_old_password: false
auto_reg: true
# allow_ips:
#  - 127.0.0.1
#  - 192.168.10.3
point_fix: 0
max_client_count: 500
pc_max_client_count: 3
# billing类型 0经典 1怀旧
bill_type: ${BILLING_GAME_SRC}

EOF

if [ ! -d "${TLBB_PATH}/Server" ]; then
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}未上传服务端执行解压操作; 正确操作：上传服务端压缩包 tlbb.tar.gz或者 tlbb.zip 到 /root 目录下，执行 untar 再执行本命令${CEND}"
    printf '%s\n' "${CRED}服务端目录已不存在: ${TLBB_PATH}/Server, 请检查解压结果${CEND}"
    exit 1
else
    # 复制已经修改好的文件到指定目录
    \cp -rf ${BASE_PATH}/tmp1 "${TLBB_PATH}/Server/Config/ServerInfo.ini"
    \cp -rf ${BASE_PATH}/tmp2 "${TLBB_PATH}/Server/Config/LoginInfo.ini"
    \cp -rf ${BASE_PATH}/tmp3 "${TLBB_PATH}/Server/Config/ShareMemInfo.ini"
    \cp -rf /etc/odbc.ini ${BASE_PATH}/odbc.ini 2>/dev/null
    \cp -rf /home/billing/config.yaml ${BASE_PATH}/config.yaml 2>/dev/null

    cd ${BASE_PATH}/ && rm -rf ${BASE_PATH}/tmp1 ${BASE_PATH}/tmp2 ${BASE_PATH}/tmp3
    chmod -R 777 ${TLBB_HOME}/billing ${TLBB_PATH} /home/billing 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}配置文件已经写入成功，可以执行【runtlbb】进行开服操作！！如需要配置在线GM，请执行【upgm】进行配置，再执行【runtlbb】进行开服操作！！${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}配置文件写入失败！${CEND}"
        exit 1
    fi
fi
