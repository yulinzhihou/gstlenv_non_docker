#!/bin/bash
# ============================================================
# tl_gslog - 查看服务端日志 (参考 gstlenv gslog)
# 用法: tl_gslog [行数]  默认最后 50 行, 实时跟踪用 -f
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
ARG="${1:-50}"
LOG=""
for f in /root/tlbb_server.log "$TLBB_HOME"/tlbb/log/*.log "$TLBB_HOME"/log/*.log; do
    [ -f "$f" ] && { LOG="$f"; break; }
done
[ -z "$LOG" ] && { echo "(未找到日志文件, 请先启动服务端)"; exit 1; }
echo "===== 日志: $LOG ====="
if [ "$ARG" = "-f" ]; then tail -f "$LOG"; else tail -n "$ARG" "$LOG"; fi
