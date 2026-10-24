#!/bin/bash
# ============================================================
# tl_runtop - 查看开服状态 (进程/端口, 参考 gstlenv runtop)
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
echo "===== 服务端进程 ====="
ps aux | grep -E "tlbb|Server|World|Login" | grep -v grep | awk '{printf "%-8s %-6s %-6s %s\n", $1,$2,$3,$11}' | head -20 || echo "(无相关进程)"
echo ""
echo "===== 关键端口监听 ====="
for p in 7777 7778 9470 3306; do
    if ss -tlnp 2>/dev/null | grep -q ":$p "; then
        echo "  [OK] 端口 $p 监听中"
    elif netstat -tlnp 2>/dev/null | grep -q ":$p "; then
        echo "  [OK] 端口 $p 监听中"
    else
        echo "  [--] 端口 $p 未监听"
    fi
done
echo ""
echo "===== 数据库 ====="
mysqladmin ping >/dev/null 2>&1 && echo "  [OK] MySQL/MariaDB 运行中" || echo "  [!!] 数据库未运行"
