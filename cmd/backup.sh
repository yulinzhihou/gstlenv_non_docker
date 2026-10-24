#!/bin/bash
# ============================================================
# tl_backup - 备份数据库 (参考 gstlenv backup, 原生 mysqldump)
# 备份至 /root/backup/
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
DB_USER="${TLBB_DB_USER:-root}"
DB_PASS="${TLBB_DB_PASS:-}"
DB_HOST="${TLBB_DB_HOST:-127.0.0.1}"
DB_PORT="${TLBB_DB_PORT:-3306}"
BK_DIR=/root/backup
mkdir -p "$BK_DIR"
STAMP=$(date +%Y%m%d%H%M%S)
DBP=""
[ -n "$DB_PASS" ] && DBP="-p${DB_PASS}"

echo "备份数据库 tlbbdb / web ..."
mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP tlbbdb > "$BK_DIR/tlbbdb_$STAMP.sql" 2>/dev/null && echo "  [OK] tlbbdb -> $BK_DIR/tlbbdb_$STAMP.sql"
mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP web > "$BK_DIR/web_$STAMP.sql" 2>/dev/null && echo "  [OK] web -> $BK_DIR/web_$STAMP.sql"
echo "备份完成, 保留最近 10 份:"
ls -t "$BK_DIR" | head -10
