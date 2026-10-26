#!/bin/bash
# ============================================================
# gstl - 环境安装初始化 (参考 gstlenv gstl.sh, 原生版)
# 检查环境是否已安装:
#   已安装 -> 显示配置(curgs) + 检查虚拟内存(swap)
#   未安装 -> 提示运行 install.sh 初始化环境
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
ENV_FILE=/root/.tlbb/tlbb.env
LOCK_FILE=/root/.tlbb/gs.lock

# 环境是否已初始化 (配置文件存在 + 数据库可连)
env_ready() {
    [ -f "$ENV_FILE" ] && mysqladmin ping >/dev/null 2>&1
}

if env_ready || [ -f "$LOCK_FILE" ]; then
    echo "${CYELLOW}GS游享环境已安装, 初始化配置参数如下:${CEND}"
    echo ""
    # 查看配置
    if command -v curgs >/dev/null 2>&1; then curgs; else . /usr/local/bin/curgs 2>/dev/null; fi
    # 检查/补充虚拟内存
    if command -v swap >/dev/null 2>&1; then swap; fi
    echo ""
    echo "${CYELLOW}GS游享环境已初始化配置参数, 如上所示, 请保管好参数. 如需重新配置, 请执行【 setconfig 】命令! 获取命令帮助请使用【 gs 】命令${CEND}"
    echo "${CYELLOW}温馨提醒: 建议更新最新的命令, 请使用【 upcmd 】${CEND}"
    exit 0
else
    echo "${CRED}GS专用环境还没初始化!${CEND}"
    echo "${CYELLOW}请先上传 src 环境包到服务器, 然后执行:${CEND}"
    echo "  cd /root/src && bash install.sh"
    echo "  (或直接运行: bash ${TLBB_PROJECT_DIR:-/opt/tlbb-env-pkg}/install.sh)"
    echo "${CYELLOW}安装完成后重新执行【 gstl 】初始化配置参数${CEND}"
    exit 1
fi
