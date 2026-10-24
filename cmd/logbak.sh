#!/bin/bash
# ============================================================
# tl_logbak - 备份日志文件 (参考 gstlenv logbak)
# 备份服务端日志到 /root/backup/logs/
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
DST=/root/backup/logs
mkdir -p "$DST"
STAMP=$(date +%Y%m%d%H%M%S)

# 常见日志目录
LOG_DIRS="$TLBB_HOME/tlbb/log $TLBB_HOME/log /root/tlbb/log"
found=0
for d in $LOG_DIRS; do
    if [ -d "$d" ] && [ "$(ls "$d" 2>/dev/null | wc -l)" -gt 0 ]; then
        tar czf "$DST/logs_$STAMP.tar.gz" -C "$(dirname "$d")" "$(basename "$d")" 2>/dev/null
        echo "[OK] 已备份 $d -> $DST/logs_$STAMP.tar.gz"
        found=1
    fi
done
[ "$found" = "0" ] && echo "(未找到日志目录)"
