#!/bin/bash
# ============================================================
# tl_restart - 重启服务端 (参考 gstlenv restart)
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
echo "重启服务端..."
tl_close 2>/dev/null || pkill -f "tlbb" 2>/dev/null
sleep 2
tl_runtlbb 2>/dev/null || bash /usr/local/bin/tl_runtlbb
