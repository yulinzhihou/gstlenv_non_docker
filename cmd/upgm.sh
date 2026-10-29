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

# comment: 一键创建在线GM管理后台 (生成 DBConfig.php + 开启 GM 工具支持)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
mkdir -p /tlgame/www/gm

# 生成 GM 网站数据库配置文件
cat >/tlgame/www/gm/DBConfig.php <<EOF
<?php
// 本文件由 gstlenv 环境自动生成, 请勿手动修改
\$DB_HOST = '127.0.0.1';
\$DB_PORT = ${TL_MYSQL_PORT:-3306};
\$DB_USER = 'root';
\$DB_PASS = '${TL_MYSQL_PASSWORD}';
\$DB_NAME = 'web';
// GM工具登录账号
\$LOGIN_USER = '${LOGIN_USER_NAME}';
\$LOGIN_PASS = '${LOGIN_PASSWORD}';
// Redis 配置 (原生未装 Redis 时仅作预留)
\$REDIS_HOST = '127.0.0.1';
\$REDIS_PORT = 6379;
\$REDIS_PASS = '${REDIS_PASSWORD}';
// GM 通信私钥
\$PRIVATE_KEY = '${PRIVATE_KEY}';
EOF

# 开启 GM 工具支持 (ScriptGlobal.lua)
GLOBAL_FILE="${TLBB_PATH}/Script/ScriptGlobal.lua"
if [ -f "${GLOBAL_FILE}" ]; then
    sed -i "s/GMDATA_ISOPEN_GMTOOLS=.*/GMDATA_ISOPEN_GMTOOLS=1/g" "${GLOBAL_FILE}" 2>/dev/null
    sed -i "s/GMDATA_PRIVATE_KEY=.*/GMDATA_PRIVATE_KEY=${PRIVATE_KEY}/g" "${GLOBAL_FILE}" 2>/dev/null
fi

chmod -R 777 /tlgame/www/gm

if [ $? -eq 0 ]; then
    echo -e "${CSUCCESS}在线GM网站配置已经生成, 目录: /tlgame/www/gm/DBConfig.php${CEND}"
    echo -e "${CYELLOW}请联系GS游享网购买在线GM软件包 https://gsgameshare.com ，客服Q：1303588722${CEND}"
    echo -e "${CYELLOW}将 GM 软件包上传到 /tlgame/www/gm 目录下, 访问方式：http://服务器IP:${WEB_GM_PORT:-61888}${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}创建失败！${CEND}"
    exit 1
fi