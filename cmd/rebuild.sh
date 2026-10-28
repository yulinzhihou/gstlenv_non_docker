#!/bin/bash
# ============================================================
# tl_rebuild - 重构环境 (参考 gstlenv rebuild, 重跑 install.sh)
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
PKG_DIR="${TLBB_PROJECT_DIR:-/root/src}"
[ -f "$PKG_DIR/install.sh" ] || { echo "[错误] 未找到 $PKG_DIR/install.sh, 请确认 src 包路径"; exit 1; }
echo "重构环境: 将重新配置源/组件/数据库/驱动 (保留数据库数据)"
read -p "确认重构? [y/N]: " ok
ok=$(echo "$ok" | tr 'A-Z' 'a-z')
[ "$ok" = "y" ] || [ "$ok" = "yes" ] || { echo "已取消"; exit 1; }
cd "$PKG_DIR" && bash install.sh "$@"
