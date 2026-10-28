#!/bin/bash
# ============================================================
# upgm - 配置在线 GM 网站 (参考 gstlenv upgm.sh, 原生版)
# 创建 GM 网站目录 /tlgame/www/gm 与数据库配置文件 DBConfig.php
# 用法: upgm
# 前置: 需将 GM 工具包 (含 GmTools.php 等文件) 上传到 /tlgame/www/gm
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
TLBB_DB_PASS="${TLBB_DB_PASS:-123456}"
TLBB_DB_PORT="${TLBB_DB_PORT:-3306}"
WWW_ROOT="${TLBB_WWW_ROOT:-/tlgame/www}"
GM_DIR="$WWW_ROOT/gm"

# 创建 GM 网站目录
mkdir -p "$GM_DIR"

# 生成默认 DBConfig.php (对齐 gstlenv 配置项)
cat >"$GM_DIR/DBConfig.php" <<EOF
<?php
 
class DBConfig
{
    // GM工具数据库配置
    public static \$db_host = '127.0.0.1';
    public static \$db_name = 'tlbbdb';
    public static \$db_user = 'root';
    public static \$db_pass = '${TLBB_DB_PASS}';
    public static \$db_port = '${TLBB_DB_PORT}';
    public static \$db_prefix = '';
    public static \$db_charset = 'utf8';
 
    // 账号数据库配置
    public static \$web_host = '127.0.0.1';
    public static \$web_name = 'web';
    public static \$web_user = 'root';
    public static \$web_pass = '${TLBB_DB_PASS}';
    public static \$web_port = '${TLBB_DB_PORT}';
    public static \$web_prefix = '';
    public static \$web_charset = 'utf8';
 
    // 业务配置
    public static \$privateKey = 'TLBB_GM_KEY';
    public static \$loginUserName = 'admin';
    public static \$loginPassword = 'admin123';
}
EOF

# 创建 gm 数据库账号表 (如需)
mysql -uroot -p"$TLBB_DB_PASS" -e "CREATE DATABASE IF NOT EXISTS gs_gmtools;" >/dev/null 2>&1

chmod -R 777 "$GM_DIR"
echo "${CSUCCESS}配置生成成功: ${GM_DIR}/DBConfig.php${CEND}"
echo "${CYELLOW}请将 GM 工具包 (含 GmTools.php 等) 上传到 ${GM_DIR} 目录${CEND}"
echo "${CYELLOW}本机部署: 将 ${GM_DIR} 挂载到 Web 服务(PHP环境) 即可访问 GM 后台${CEND}"
echo "${CYELLOW}访问方式: http://IP地址:网站端口/gm/${CEND}"
echo "${CYELLOW}默认 GM 登录账号: admin / admin123 (请登录后立即修改)${CEND}"
echo "${CWARNING}注意: GM 工具需服务端 ScriptGlobal.lua 开启 GMDATA_ISOPEN_GMTOOLS 才生效${CEND}"
exit 0
