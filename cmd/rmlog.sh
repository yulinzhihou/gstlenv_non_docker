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

# comment: 删除调试日志，防止服务端启动时间长，导致服务器硬盘被日志挤爆
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"

# 先判断目录是否存在
if [ -d ${TLBB_PATH}"/Server/Log" ]; then
    rm -rf ${TLBB_PATH}"/Server/Log"
fi

if [ $? -eq 0 ]; then
    echo -e "${CSUCCESS} 清理成功！如果需要重新打开，请使用【gslog】,请使用完一定记得关闭。小心挤爆服务器硬盘！${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    exit 1
fi
