#!/bin/bash
# ============================================================
# link - 进入服务端目录命令行 (参考 gstlenv link.sh, 原生版)
# 原生环境无容器概念, 直接进入服务端/工作目录
# 用法:
#   link                进入服务端目录 ${TLBB_HOME}
#   link server|s       同上
#   link mysql|m        直接进入 mysql 命令行
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"

[ -d "$TLBB_HOME" ] || { echo "${CRED}环境未安装或服务端目录不存在: $TLBB_HOME${CEND}"; echo "${CRED}请先执行 gstl / install.sh 初始化环境${CEND}"; exit 1; }

if [ $# -eq 0 ]; then
    echo "${CYELLOW}进入服务端目录: ${TLBB_HOME}${CEND}"
    cd "$TLBB_HOME" || exit 1
    exec /bin/bash
else
    case "$1" in
        'mysql'|'sql'|'my'|'m')
            echo "${CYELLOW}进入数据库命令行 (退出请输 exit)${CEND}"
            exec mysql -uroot -p"${TLBB_DB_PASS:-root}" 2>/dev/null || exec mysql -uroot
            ;;
        'server'|'gs'|'s')
            echo "${CYELLOW}进入服务端目录: ${TLBB_HOME}${CEND}"
            cd "$TLBB_HOME" || exit 1
            exec /bin/bash
            ;;
        *)
            echo "${CRED}错误: 输入有误!! 请使用 link {mysql|sql|my|m},{server|gs|s}, 或不带参数进入服务端目录${CEND}"
            exit 1
            ;;
    esac
fi
