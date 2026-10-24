#!/bin/bash
# ============================================================
# tl_setini - 配置服务端 ini 文件 (参考 gstlenv setini)
# 自动写入: 数据库IP/端口/密码/账号 到服务端 config/ServerInfo.ini
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
DB_HOST="${TLBB_DB_HOST:-127.0.0.1}"
DB_PORT="${TLBB_DB_PORT:-3306}"
DB_USER="${TLBB_DB_USER:-root}"
DB_PASS="${TLBB_DB_PASS:-}"

# 定位服务端目录 (支持 tlbb 或 Home 等常见目录名)
SERV_DIR=""
for d in "$TLBB_HOME"/tlbb "$TLBB_HOME"/Home "$TLBB_HOME"; do
    [ -d "$d/config" ] && { SERV_DIR="$d"; break; }
done
[ -z "$SERV_DIR" ] && { echo "[错误] 未找到服务端 config 目录, 请先 tl_untar"; exit 1; }

INI="$SERV_DIR/config/ServerInfo.ini"
if [ ! -f "$INI" ]; then
    # 兜底: 从样例生成
    find "$SERV_DIR" -name "ServerInfo*.ini*" 2>/dev/null | head -1 | while read -r f; do cp -f "$f" "$INI"; done
    [ -f "$INI" ] || { echo "[错误] 未找到 ServerInfo.ini 模板"; exit 1; }
fi

# 备份原配置
cp -f "$INI" "$INI.bak.$(date +%Y%m%d%H%M%S)"

# 写入数据库配置 (兼容各版本 ini 字段)
sed -i "s/^\(DBIP\|DBIp\|MYSQLIP\|IP\)=.*/\1=${DB_HOST}/Ig" "$INI"
sed -i "s/^\(DBPORT\|MYSQLPORT\|PORT\)=.*/\1=${DB_PORT}/Ig" "$INI"
sed -i "s/^\(DBUSER\|USER\|MYSQLUSER\)=.*/\1=${DB_USER}/Ig" "$INI"
sed -i "s/^\(DBPASS\|PASSWORD\|MYSQLPASS\|PWD\)=.*/\1=${DB_PASS}/Ig" "$INI"
# 若字段不存在则追加
grep -qiE '^DBIP=' "$INI" || echo "DBIP=${DB_HOST}" >> "$INI"
grep -qiE '^DBPORT=' "$INI" || echo "DBPORT=${DB_PORT}" >> "$INI"
grep -qiE '^DBUSER=' "$INI" || echo "DBUSER=${DB_USER}" >> "$INI"
grep -qiE '^DBPASS=' "$INI" || echo "DBPASS=${DB_PASS}" >> "$INI"

chmod -R 777 "$SERV_DIR" 2>/dev/null
echo "[OK] ServerInfo.ini 配置完成: $INI"
echo "  数据库: $DB_HOST:$DB_PORT  $DB_USER/${DB_PASS:-未设置}"
echo "下一步: tl_runtlbb 开启服务端"
