#!/usr/bin/env bash
# 设置字符编码，确保中文正常显示
{
    export LANG=C.UTF-8 2>/dev/null || export LANG=en_US.UTF-8 2>/dev/null || export LANG=POSIX 2>/dev/null || true
    export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX 2>/dev/null || true
} 2>/dev/null
# 引入全局参数
[ -f /root/.gs/.env ] && . /root/.gs/.env
# 颜色代码
[ -f /usr/local/bin/color ] && . /usr/local/bin/color

# comment: 查看服务器进程情况 (原生: 本机进程 + 端口监听, 对齐 gstlenv runtop 用途)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

echo "===== 服务端进程 (ShareMemory / Login / World / Server / billing) ====="
ps aux | grep -E "ShareMemory|Login|World|Server|billing" | grep -v grep | awk '{printf "%-10s %-8s %-6s %s\n", $1, $2, $3, $11}' | head -20
echo ""
echo "===== 关键端口监听 (gstlenv 默认) ====="
MYSQL_PORT="${TL_MYSQL_PORT:-3306}"
LOGIN_PORT="${LOGIN_PORT:-13580}"
SERVER_PORT="${SERVER_PORT:-15680}"
BILLING_PORT="${BILLING_PORT:-21818}"
for p in ${MYSQL_PORT} ${LOGIN_PORT} ${SERVER_PORT} ${BILLING_PORT}; do
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
mysqladmin ping >/dev/null 2>&1 && echo "  [OK] MySQL 运行中" || echo "  [!!] 数据库未运行"
