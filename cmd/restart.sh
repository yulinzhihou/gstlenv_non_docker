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

# comment: 重启服务端命令 (默认只重启服务端; 输入1则全部服务重启)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

for ((time = 5; time >= 0; time--)); do
    echo -ne "\r在准备正行重启服务端操作！！，剩余 ${CYELLOW}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
    sleep 1
done
echo -ne "\n\r"
echo -ne "${CYELLOW}正在重启服务端，请稍候……${CEND}\r\n"

while :; do
    echo
    read -e -p "${CYELLOW}是否需要重启所有服务(含数据库) [y/n](默认: n): ${CEND}" IS_RESTART_ALL
    IS_RESTART_ALL=${IS_RESTART_ALL:-'n'}
    if [[ ! ${IS_RESTART_ALL} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
    else
        # 关闭服务端
        close >/dev/null 2>&1
        if [ "${IS_RESTART_ALL}" == 'y' ]; then
            echo -e "${CYELLOW}正在重启数据库……${CEND}"
            systemctl restart mysqld 2>/dev/null || systemctl restart mysql 2>/dev/null || service mysqld restart 2>/dev/null || service mysql restart 2>/dev/null || true
        fi
        # 启动服务端
        runtlbb
        break
    fi
done

if [ $? -eq 0 ]; then
    echo -e "${CSUCCESS}服务端已经重启成功，如有疑问，可执行【runtop】查看开服状态！！${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}服务端重启失败！${CEND}"
    exit 1
fi
