#!/bin/bash
# ============================================================
# tl_untar - 解压服务端压缩包 (参考 gstlenv untar)
# 条件: 将 tlbb.tar.gz 或 tlbb.zip 上传至 /root 目录
# 解压到: ${TLBB_HOME:-/home/tlbb}
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
mkdir -p "$TLBB_HOME"

if [ -f /root/tlbb.tar.gz ]; then
    # 备份旧端
    if [ -d "$TLBB_HOME/tlbb" ]; then
        mv "$TLBB_HOME/tlbb" "$TLBB_HOME/tlbb.bak.$(date +%Y%m%d%H%M%S)"
        echo "[TLBB] 旧端已备份至 $TLBB_HOME"
    fi
    tar zxf /root/tlbb.tar.gz -C "$TLBB_HOME"
    mv /root/tlbb.tar.gz "/root/$(date +%Y%m%d%H%M%S)-tlbb.tar.gz" 2>/dev/null
    echo "[OK] tlbb.tar.gz 解压完成 -> $TLBB_HOME"
    echo "下一步: tl_setini 写入配置"
    exit 0
elif [ -f /root/tlbb.zip ]; then
    if [ -d "$TLBB_HOME/tlbb" ]; then
        mv "$TLBB_HOME/tlbb" "$TLBB_HOME/tlbb.bak.$(date +%Y%m%d%H%M%S)"
    fi
    command -v unzip >/dev/null 2>&1 || { echo "缺少 unzip, 请先安装"; exit 1; }
    unzip -q /root/tlbb.zip -d "$TLBB_HOME"
    mv /root/tlbb.zip "/root/$(date +%Y%m%d%H%M%S)-tlbb.zip" 2>/dev/null
    echo "[OK] tlbb.zip 解压完成 -> $TLBB_HOME"
    echo "下一步: tl_setini 写入配置"
    exit 0
else
    echo "[错误] 未找到服务端压缩包, 请上传 tlbb.tar.gz 或 tlbb.zip 到 /root 目录"
    exit 1
fi
