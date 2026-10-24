#!/bin/bash
# ============================================================
# tl_restore - 还原数据库 (参考 gstlenv restore)
# 用法: tl_restore [备份文件]   默认还原 /root/backup 最新备份
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
DB_USER="${TLBB_DB_USER:-root}"
DB_PASS="${TLBB_DB_PASS:-}"
DB_HOST="${TLBB_DB_HOST:-127.0.0.1}"
DB_PORT="${TLBB_DB_PORT:-3306}"
BK_DIR=/root/backup
DBP=""
[ -n "$DB_PASS" ] && DBP="-p${DB_PASS}"

FILE="${1:-}"
if [ -z "$FILE" ]; then
    FILE=$(ls -t "$BK_DIR"/tlbbdb_*.sql 2>/dev/null | head -1)
    [ -z "$FILE" ] && { echo "[错误] 未找到备份, 请指定文件或先执行 tl_backup"; exit 1; }
fi
[ -f "$FILE" ] || { echo "[错误] 文件不存在: $FILE"; exit 1; }

echo "还原数据库 (库: tlbbdb) 从 $FILE ..."
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP tlbbdb < "$FILE" && echo "[OK] tlbbdb 还原完成" || echo "[失败] 还原失败, 请检查文件与库结构"
