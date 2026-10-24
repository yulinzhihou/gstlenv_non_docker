#!/bin/bash
# ============================================================
# tl_setpoint - 设置账号默认充值点数 (参考 gstlenv setpoint)
# 用法: tl_setpoint [账号] [点数]
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
DB_USER="${TLBB_DB_USER:-root}"
DB_PASS="${TLBB_DB_PASS:-}"
DB_HOST="${TLBB_DB_HOST:-127.0.0.1}"
DB_PORT="${TLBB_DB_PORT:-3306}"
DBP=""
[ -n "$DB_PASS" ] && DBP="-p${DB_PASS}"

ACC="${1:-}"
POINT="${2:-1000}"
[ -z "$ACC" ] && { echo "用法: tl_setpoint [账号] [点数]"; exit 1; }

# 常见字段: 各版本 tlbbdb 充值点数字段名不一 (points/remain_point/bind_yuanbao 等)
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP tlbbdb -e "UPDATE t_account SET points=${POINT} WHERE name='${ACC}';" 2>/dev/null && echo "[OK] tlbbdb 已设置 ${ACC} 点数=${POINT}"
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $DBP tlbbdb -e "UPDATE account SET points=${POINT} WHERE name='${ACC}';" 2>/dev/null && echo "[OK] account 已设置 ${ACC} 点数=${POINT}"
echo "若未生效, 请确认点数字段名 (可查看 tlbbdb.sql 中 t_account 表结构)"
