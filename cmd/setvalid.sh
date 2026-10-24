#!/bin/bash
# ============================================================
# tl_setvalid - 解/封号 (参考 gstlenv setvalid)
# 用法: tl_setvalid [账号] [0=解封|1=封号]
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
DB_USER="${TLBB_DB_USER:-root}"
DB_PASS="${TLBB_DB_PASS:-}"
DB_HOST="${TLBB_DB_HOST:-127.0.0.1}"
DB_PORT="${TLBB_DB_PORT:-3306}"
DBP=""
[ -n "$DB_PASS" ] && DBP="-p${DB_PASS}"

ACC="${1:-}"
[ -z "$ACC" ] && { echo "用法: tl_setvalid [账号] [0解封|1封号]"; exit 1; }
VAL="${2:-0}"

# 常见账号表结构: account(web库) / t_account(tlbbdb) / 各版本字段可能为 validflag
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP web -e "UPDATE account SET validflag=${VAL} WHERE name='${ACC}';" 2>/dev/null && echo "[OK] web.account 已更新 ${ACC} -> validflag=${VAL}"
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP tlbbdb -e "UPDATE t_account SET validflag=${VAL} WHERE name='${ACC}';" 2>/dev/null && echo "[OK] tlbbdb.t_account 已更新 ${ACC} -> validflag=${VAL}"
echo "若以上均无输出, 请手动确认账号表名与字段 (可用 tl_curgs 查看库信息)"
