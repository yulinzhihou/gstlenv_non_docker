#!/bin/bash
# ============================================================
# tl_remove - 卸载环境 (参考 gstlenv remove)
# 停止服务端/数据库, 移除 tl_* 命令 (不删除数据库数据, 需手动)
# ============================================================
[ "$(id -u)" != "0" ] && { echo "错误: 必须使用 root 用户"; exit 1; }
echo "!!! 即将卸载 TLBB 环境 (停止服务, 移除命令) !!!"
read -p "确认卸载? 输入 YES 继续: " ok
ok=$(echo "$ok" | tr 'a-z' 'A-Z')
[ "$ok" != "YES" ] && { echo "已取消"; exit 1; }

tl_close 2>/dev/null
systemctl stop mysqld 2>/dev/null; systemctl stop mysql 2>/dev/null; systemctl stop mariadb 2>/dev/null
service mysqld stop 2>/dev/null; service mysql stop 2>/dev/null

# 移除全局命令
for f in /usr/local/bin/tl /usr/local/bin/tl_*; do
    [ -f "$f" ] && rm -f "$f"
done
echo "[OK] 服务已停止, tl_* 命令已移除"
echo "说明: 数据库数据保留 (/var/lib/mysql), 如需彻底删除请手动执行: rm -rf /var/lib/mysql"
echo "      服务端文件保留 (/home/tlbb), 如需删除: rm -rf /home/tlbb"
