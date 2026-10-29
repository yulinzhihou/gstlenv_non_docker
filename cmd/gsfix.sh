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

# comment: 修复环境安装 (原生版: 重部署命令/检查数据库/检查ODBC)
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

echo -e "${CYELLOW}正在修复环境安装……${CEND}"
# 1. 重新部署命令
if [ -d "${GS_PROJECT:-/root/.tlgame}/cmd" ]; then
    upcmd >/dev/null 2>&1
    echo -e "${CSUCCESS}命令已重新部署${CEND}"
else
    echo -e "${CWARNING}未找到 cmd/ 目录, 跳过命令部署${CEND}"
fi
# 2. 检查数据库
if mysqladmin ping >/dev/null 2>&1; then
    echo -e "${CSUCCESS}MySQL 数据库运行正常${CEND}"
else
    echo -e "${CRED}MySQL 数据库未运行, 请尝试: systemctl start mysqld 或 service mysqld start${CEND}"
fi
# 3. 检查 ODBC
if [ -f /etc/odbc.ini ]; then
    echo -e "${CSUCCESS}ODBC 配置存在 (/etc/odbc.ini)${CEND}"
else
    echo -e "${CWARNING}ODBC 配置缺失, 请上传服务端后执行【setini】重新生成${CEND}"
fi
# 4. 检查目录
mkdir -p /tlgame/backup /tlgame/www/ow /tlgame/www/gm 2>/dev/null
echo -e "${CSUCCESS}环境修复完成, 如有问题请提交: https://gitee.com/yulinzhihou/gstlenv/issues${CEND}"
exit 0