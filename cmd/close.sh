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

# comment: 关闭服务端命令 (原生: 结束 TLBB 相关进程)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

# 结束 TLBB 引擎进程与 billing
for p in billing ShareMemory Login World Server; do
    pkill -x $p 2>/dev/null
done
# 结束 run.sh 启动进程 (防止残留拉起)
pkill -f "${TLBB_PATH:-/tlgame/tlbb}/run.sh" 2>/dev/null

sleep 2

if pgrep -x Server >/dev/null 2>&1 || pgrep -x World >/dev/null 2>&1 || pgrep -x Login >/dev/null 2>&1; then
    echo -e "${CRED}服务端部分进程未完全关闭，请稍后重试或手动 pkill 结束${CEND}"
    exit 1
else
    echo -e "${CSUCCESS}已经成功关闭服务端!${CEND}"
    exit 0
fi
