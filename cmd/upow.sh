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

# comment: 一键创建开服网站 (OW: 官网, 上传到 /tlgame/www/ow)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

mkdir -p /tlgame/www/ow

if [ $? -eq 0 ]; then
    echo -e "${CSUCCESS}创建成功，请将网站上传到/tlgame/www/ow目录里面，并且首页必须是index.html index.htm default.html default.htm中的一种${CEND}"
    echo -e "${CWARNING}访问方式：http://服务器IP:${WEB_PORT:-51888} 进行访问${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}创建失败！${CEND}"
    exit 1
fi