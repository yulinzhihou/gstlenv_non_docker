#!/bin/bash
# ============================================================
# tl_change - 换端 (参考 gstlenv change)
# 用法: tl_change  将 /root/tlbb.tar.gz 换为新端并备份旧端
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
[ -f /root/tlbb.tar.gz ] || { echo "[错误] 请先将新端 tlbb.tar.gz 上传到 /root"; exit 1; }

echo "换端: 备份旧端 -> 解压新端"
tl_close 2>/dev/null
sleep 2
if [ -d "$TLBB_HOME/tlbb" ]; then
    mv "$TLBB_HOME/tlbb" "$TLBB_HOME/tlbb.bak.$(date +%Y%m%d%H%M%S)"
    echo "[OK] 旧端已备份"
fi
tar zxf /root/tlbb.tar.gz -C "$TLBB_HOME"
mv /root/tlbb.tar.gz "/root/$(date +%Y%m%d%H%M%S)-tlbb.tar.gz" 2>/dev/null
echo "[OK] 新端已解压, 请执行: tl_setini && tl_runtlbb"
