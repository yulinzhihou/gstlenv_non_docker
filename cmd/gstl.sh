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

# comment: 环境安装初始化 (原生版: 已安装则显示配置, 未安装提示运行 install.sh)
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

if [ -f /root/.gs/.env ] && [ -d /tlgame ]; then
    echo -e "${CSUCCESS}GS专用环境已经安装过了，请使用【gs】查看命令帮助！${CEND}"
    curgs 2>/dev/null
    # 虚拟内存检查
    if [ ! -f /usr/swap/swapfile ]; then
        echo -e "${CYELLOW}检测到未配置虚拟内存, 建议执行【swap】增加虚拟缓存(默认4G)${CEND}"
    fi
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}GS专用环境还没初始化! 请先执行环境包安装: bash install.sh 进行安装${CEND}"
    exit 1
fi