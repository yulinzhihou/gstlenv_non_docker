#!/bin/bash
# ============================================================
# tl_rmlog - 清理日志 (参考 gstlenv rmlog)
# 用法: tl_rmlog  删除服务端 7 天前日志 (保留当天)
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
echo "清理日志 (删除 7 天前 .log 文件)..."
for d in "$TLBB_HOME/tlbb/log" "$TLBB_HOME/log" /root/tlbb/log; do
    [ -d "$d" ] || continue
    # 保留当天的 log, 删除旧日志
    find "$d" -name "*.log" -mtime +7 -delete 2>/dev/null
    echo "  已清理: $d"
done
rm -f /root/tlbb_server.log.* 2>/dev/null
echo "[OK] 日志清理完成"
