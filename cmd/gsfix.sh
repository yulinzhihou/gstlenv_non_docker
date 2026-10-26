#!/bin/bash
# ============================================================
# gsfix - 修复环境安装 (参考 gstlenv gsfix.sh, 原生版)
# 重新检查/补装核心组件: 32位兼容库 + unixODBC + ODBC驱动 + 数据库
# 不需要 Docker, 直接修复本机环境
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
PROJECT_DIR="${TLBB_PROJECT_DIR:-/opt/tlbb-env-pkg}"

echo "${CYELLOW}开始修复 TLBB 原生环境...${CEND}"

# 1. 判定系统
if [ -f /etc/redhat-release ] || grep -qiE 'centos|redhat|alibaba|anolis|tencentos|openeuler|rocky|alma|oracle|fedora' /etc/os-release 2>/dev/null; then
    SYS=rhel
elif grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    SYS=debian
else
    echo "${CRED}无法识别系统!${CEND}"; exit 1
fi

fix_rhel() {
    echo "${CYELLOW}[RHEL系] 检查 32 位兼容库与 unixODBC...${CEND}"
    command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || { echo "${CRED}缺少 yum/dnf${CEND}"; return 1; }
    local m; command -v dnf >/dev/null 2>&1 && m=dnf || m=yum
    $m -y install glibc.i686 libstdc++.i686 libnsl.i686 libcrypt.i686 zlib.i686 unixODBC unixODBC-devel >/dev/null 2>&1 || \
        $m -y install glibc.i686 libstdc++.i686 unixODBC >/dev/null 2>&1 || \
        echo "${CWARNING}部分 32 位库安装失败(可尝试离线包)${CEND}"
    # 离线驱动兜底
    local drv; drv=$(find "$PROJECT_DIR" /opt /root /home -name "libmyodbc3-3.51.27.so" 2>/dev/null | head -1)
    if [ -n "$drv" ]; then
        mkdir -p /usr/lib
        cp -f "$drv" /usr/lib/libmyodbc3.so
        [ -f /usr/lib64/libmyodbc5w.so ] || { local d64; d64=$(find "$PROJECT_DIR" /opt /root /home -name "libmyodbc5w.so" 2>/dev/null | head -1); [ -n "$d64" ] && cp -f "$d64" /usr/lib64/libmyodbc.so 2>/dev/null; }
        echo "${CSUCCESS}ODBC 驱动已就位${CEND}"
    fi
}

fix_debian() {
    echo "${CYELLOW}[Debian系] 检查 32 位兼容库与 unixODBC...${CEND}"
    dpkg --add-architecture i386 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libc6:i386 libstdc++6:i386 unixodbc:i386 unixodbc libodbc2:i386 >/dev/null 2>&1 || \
        echo "${CWARNING}部分 32 位库安装失败(可尝试离线包)${CEND}"
    local drv; drv=$(find "$PROJECT_DIR" /opt /root /home -name "libmyodbc3-3.51.27.so" 2>/dev/null | head -1)
    if [ -n "$drv" ]; then
        mkdir -p /usr/lib/i386-linux-gnu
        cp -f "$drv" /usr/lib/i386-linux-gnu/libmyodbc3.so
        echo "${CSUCCESS}ODBC 驱动已就位${CEND}"
    fi
}

# 2. 修复数据库
fix_db() {
    if ! mysqladmin ping >/dev/null 2>&1; then
        echo "${CYELLOW}数据库未运行, 尝试启动...${CEND}"
        if [ "$SYS" = "rhel" ]; then
            service mysqld start 2>/dev/null || service mysql start 2>/dev/null || systemctl start mariadb 2>/dev/null || true
        else
            service mariadb start 2>/dev/null || service mysql start 2>/dev/null || systemctl start mariadb 2>/dev/null || true
        fi
        sleep 4
        mysqladmin ping >/dev/null 2>&1 && echo "${CSUCCESS}数据库已启动${CEND}" || \
            echo "${CWARNING}数据库启动失败, 请检查安装或日志${CEND}"
    else
        echo "${CSUCCESS}数据库运行正常${CEND}"
    fi
}

# 3. 检查服务端目录与 ODBC 配置
fix_tlbb() {
    [ -d "$TLBB_HOME" ] && echo "${CSUCCESS}服务端目录 ${TLBB_HOME} 就位${CEND}" || { mkdir -p "$TLBB_HOME"; echo "${CYELLOW}已创建 ${TLBB_HOME}${CEND}"; }
    [ -f /etc/odbc.ini ] && echo "${CSUCCESS}ODBC 配置就位 (/etc/odbc.ini)${CEND}" || \
        echo "${CWARNING}缺少 /etc/odbc.ini, 请执行 setini 或重新安装${CEND}"
}

case "$SYS" in
    rhel) fix_rhel;;
    debian) fix_debian;;
esac
fix_db
fix_tlbb

echo ""
echo "${CSUCCESS}环境修复完成. 如仍有问题: 1) 检查离线组件 2) 查看日志: gslog${CEND}"
echo "${CYELLOW}提示: 修复不会删除数据, 如需彻底重建请使用 rebuild${CEND}"
exit 0
