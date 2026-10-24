#!/bin/bash
# ============================================================
# tl_runtlbb - 开启 TLBB 服务端 (参考 gstlenv runtlbb)
# 定位服务端启动脚本并后台启动
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"

# 查找启动脚本
RUN_SCRIPT=""
for c in "$TLBB_HOME"/tlbb/run.sh "$TLBB_HOME"/Home/run.sh "$TLBB_HOME"/run.sh "$TLBB_HOME"/tlbb/StartServer.sh; do
    [ -f "$c" ] && { RUN_SCRIPT="$c"; break; }
done
[ -z "$RUN_SCRIPT" ] && { echo "[错误] 未找到启动脚本 (run.sh), 请检查服务端"; exit 1; }

SERV_DIR=$(dirname "$RUN_SCRIPT")
cd "$SERV_DIR" || exit 1
chmod +x "$RUN_SCRIPT" 2>/dev/null

# 后台启动
nohup bash "$RUN_SCRIPT" > /root/tlbb_server.log 2>&1 &
sleep 3
if pgrep -f "tlbb" >/dev/null 2>&1 || pgrep -f "Server" >/dev/null 2>&1; then
    echo "[OK] 服务端已启动 (日志: /root/tlbb_server.log)"
else
    echo "[警告] 未能确认进程, 请查看日志: /root/tlbb_server.log"
fi
echo "查看状态: tl_runtop   关闭: tl_close"
