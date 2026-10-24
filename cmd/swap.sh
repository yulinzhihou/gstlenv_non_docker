#!/bin/bash
# ============================================================
# tl_swap - 增加虚拟内存 (参考 gstlenv swap)
# 用法: tl_swap [大小GB]   默认 4GB, 已存在则追加文件
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
GB="${1:-4}"
SWAPFILE=/root/tlbb_swapfile
CURRENT=$(free -m | awk '/Swap:/{print $2}')

echo "当前 Swap: ${CURRENT}MB, 将新增 ${GB}GB"
if [ -f "$SWAPFILE" ]; then
    echo "已存在 $SWAPFILE, 跳过创建 (如需扩容请手动删除后重跑)"
else
    dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((GB*1024)) 2>/dev/null
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null 2>&1
    swapon "$SWAPFILE" 2>/dev/null && echo "[OK] Swap 已启用"
    grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE swap swap defaults 0 0" >> /etc/fstab
fi
free -m | awk '/Swap:/{print "当前 Swap: "$2"MB (已用 "$3"MB)"}'
