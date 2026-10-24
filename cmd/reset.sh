#!/bin/bash
# ============================================================
# tl_reset - 删档并重导 tlbbdb/web 库 (参考 gstlenv reset)
# 注意: 会清空所有玩家数据! 执行前建议 tl_backup
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
DB_USER="${TLBB_DB_USER:-root}"
DB_PASS="${TLBB_DB_PASS:-}"
DB_HOST="${TLBB_DB_HOST:-127.0.0.1}"
DB_PORT="${TLBB_DB_PORT:-3306}"
DBP=""
[ -n "$DB_PASS" ] && DBP="-p${DB_PASS}"

echo "!!! 即将清空 tlbbdb / web 两个库并重导初始数据 !!!"
read -p "确认删档? 输入 YES 继续: " ok
[ "$ok" != "YES" ] && { echo "已取消"; exit 1; }

echo "请选择初始数据源:"
echo "  1) 安装包内置 (offline/sql/)"
echo "  2) /root/backup 最新备份"
read -p "选择 [1/2]: " src
src="${src:-1}"

SQL_DIR=""
if [ "$src" = "2" ]; then
    SQL_DIR=/root/backup
else
    # 定位安装包 offline/sql
    for d in /root/tlbb-env /root/src /opt/tlbb /root; do :; done
    SQL_DIR=$(find /root -type d -name sql -path "*offline*" 2>/dev/null | head -1)
    [ -z "$SQL_DIR" ] && SQL_DIR=$(dirname "$(find /root -name tlbbdb.sql 2>/dev/null | head -1)" 2>/dev/null)
    [ -z "$SQL_DIR" ] && { echo "[错误] 未找到 offline/sql 目录"; exit 1; }
fi

mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP -e "DROP DATABASE IF EXISTS tlbbdb; DROP DATABASE IF EXISTS web; CREATE DATABASE tlbbdb DEFAULT CHARACTER SET utf8; CREATE DATABASE web DEFAULT CHARACTER SET utf8;" 2>/dev/null

# 还原: 备份模式用文件名, 内置模式用 tlbbdb.sql/web.sql
if [ "$src" = "2" ]; then
    TB=$(ls -t /root/backup/tlbbdb_*.sql 2>/dev/null | head -1)
    WB=$(ls -t /root/backup/web_*.sql 2>/dev/null | head -1)
    [ -n "$TB" ] && mysql -h"$DB_HOST" -u"$DB_USER" $DBP tlbbdb < "$TB" 2>/dev/null && echo "[OK] tlbbdb 还原"
    [ -n "$WB" ] && mysql -h"$DB_HOST" -u"$DB_USER" $DBP web < "$WB" 2>/dev/null && echo "[OK] web 还原"
else
    mysql -h"$DB_HOST" -u"$DB_USER" $DBP tlbbdb < "$SQL_DIR/tlbbdb.sql" 2>/dev/null && echo "[OK] tlbbdb 导入"
    mysql -h"$DB_HOST" -u"$DB_USER" $DBP web < "$SQL_DIR/web.sql" 2>/dev/null && echo "[OK] web 导入"
fi
echo "[完成] 删档重导完成, 请重启服务端生效: tl_restart"
