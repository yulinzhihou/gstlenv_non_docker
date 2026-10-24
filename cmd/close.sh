#!/bin/bash
# ============================================================
# tl_close - 关闭服务端 (参考 gstlenv close)
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
echo "正在关闭 TLBB 服务端进程..."
pkill -f "tlbb" 2>/dev/null
pkill -f "World" 2>/dev/null
pkill -f "Login" 2>/dev/null
pkill -f "Server" 2>/dev/null
sleep 2
if pgrep -f "tlbb" >/dev/null 2>&1; then
    echo "[警告] 部分进程仍在运行, 尝试强制结束"
    pkill -9 -f "tlbb" 2>/dev/null
fi
echo "[OK] 服务端已关闭"
