#!/bin/bash
# ============================================================
# tl_curgs - 查看当前环境配置 (参考 gstlenv curgs)
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
echo "===== 运行环境 (/root/.tlbb/tlbb.env) ====="
grep -vE '^\s*#|^\s*$' /root/.tlbb/tlbb.env 2>/dev/null | sed 's/\(PASS=\).*/\1******/'
echo ""
echo "===== ODBC 配置 (/etc/odbc.ini) ====="
[ -f /etc/odbc.ini ] && grep -vE '^\s*#|^\s*$' /etc/odbc.ini | sed 's/\(Password=\).*/\1******/' || echo "(未配置)"
echo ""
echo "===== 数据库 ====="
mysql -N -e "SELECT VERSION();" 2>/dev/null | head -1 && mysql -N -e "SHOW DATABASES LIKE 'tlbbdb'; SHOW DATABASES LIKE 'web';" 2>/dev/null || echo "(数据库未运行)"
echo ""
echo "===== 服务端目录 ====="
ls -d "${TLBB_HOME:-/home/tlbb}"/*/ 2>/dev/null | head -5 || echo "(未解压服务端)"
