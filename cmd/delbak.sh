#!/bin/bash
# ============================================================
# tl_delbak - 删除备份文件 (参考 gstlenv delbak)
# 用法: tl_delbak [保留份数]  默认保留最近 5 份
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
KEEP="${1:-5}"
BK_DIR=/root/backup
[ -d "$BK_DIR" ] || { echo "无备份目录"; exit 0; }
total=$(ls "$BK_DIR" | wc -l)
if [ "$total" -le "$KEEP" ]; then
    echo "备份共 ${total} 份, 无需清理"
    exit 0
fi
# 删除最旧的 (超出保留数)
ls -t "$BK_DIR" | tail -n $((total-KEEP)) | while read -r f; do
    rm -f "$BK_DIR/$f"
    echo "  删除: $f"
done
echo "[OK] 已清理至最近 ${KEEP} 份"
