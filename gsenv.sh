#!/usr/bin/env bash
# ============================================================
# GS游享网 · 天龙八部万能环境 (非 Docker) —— 在线一键安装引导
# ------------------------------------------------------------
# 项目: https://github.com/yulinzhihou/gstlenv_non_docker
# 参考: gstlenv(Docker版) 的 gsenv.sh 一键安装流程, 本脚本为原生版
# ------------------------------------------------------------
# 用法(在线安装, root 下执行):
#   curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash -s -- --online
#   curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash -s -- --dbpass mypass
# 离线安装(无网络, 需先把离线组件附件解压到 /root/tlbb离线组件/):
#   curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash -s -- --offline
# ------------------------------------------------------------
# 流程: 检测root -> 展示广告 -> 下载仓库源码 -> 部署到 /root/.tlgame
#       -> 执行 install.sh (透传参数)
# ============================================================

export LC_ALL=C

# ---------- 颜色 ----------
CRED='\033[31m'; CGREEN='\033[32m'; CYELLOW='\033[33m'; CBLUE='\033[34m'; CPURPLE='\033[35m'; CCYAN='\033[36m'; CEND='\033[0m'

# ---------- 检测 root ----------
[ "$(id -u)" != "0" ] && {
    echo -e "${CRED}错误: 在线安装必须使用 ROOT 用户执行!${CEND}"
    echo -e "${CYELLOW}请先执行: sudo su - 切换到 root 后再运行${CEND}"
    exit 1
}

# ---------- 展示广告 ----------
brand_banner() {
    echo ""
    echo -e "${CPURPLE}==============================================================${CEND}"
    echo -e "${CCYAN}      GS游享网 · 天龙八部 万能环境 (非 Docker 原生版)${CEND}"
    echo -e "${CPURPLE}==============================================================${CEND}"
    echo -e "${CGREEN}  官网: https://gsgameshare.com${CEND}"
    echo -e "${CGREEN}  项目: https://github.com/yulinzhihou/gstlenv_non_docker${CEND}"
    echo -e "${CYELLOW}  本环境仅供学习研究使用, 请在 24 小时内删除, 勿用于商业用途${CEND}"
    echo -e "${CPURPLE}==============================================================${CEND}"
    echo ""
}

# ---------- 变量 ----------
REPO="yulinzhihou/gstlenv_non_docker"
BRANCH="main"
SRC_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"
GIT_URL="https://github.com/${REPO}.git"
ENV_DIR="/root/.tlgame"
TMP_TAR="/tmp/gstlenv_non_docker.tar.gz"

# ---------- 下载源码 ----------
download() {
    echo -e "${CYELLOW}正在下载 TLBB 万能环境源码 (在线安装) ...${CEND}"
    rm -rf /tmp/gstlenv_src /tmp/gstlenv_non_docker-main "${TMP_TAR}"

    # 方式一: codeload tar.gz (推荐, 无需预装 git)
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 600 "${SRC_URL}" -o "${TMP_TAR}" && return 0
    elif command -v wget >/dev/null 2>&1; then
        wget -T 60 -O "${TMP_TAR}" "${SRC_URL}" && return 0
    fi

    # 方式二: git clone (curl/wget 均失败或超时)
    echo -e "${CYELLOW}codeload 下载失败, 改用 git clone ...${CEND}"
    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 -b "${BRANCH}" "${GIT_URL}" /tmp/gstlenv_src && return 0
    fi

    echo -e "${CRED}错误: 源码下载失败! 请检查网络, 或手动 git clone ${GIT_URL}${CEND}"
    exit 1
}

# ---------- 解压/部署 ----------
deploy() {
    echo -e "${CYELLOW}正在部署环境源码到 ${ENV_DIR} ...${CEND}"
    if [ -d /tmp/gstlenv_src ]; then
        # git clone 模式: 目录即源码
        if [ -d "${ENV_DIR}" ] && [ -f "${ENV_DIR}/install.sh" ]; then
            echo -e "${CYELLOW}检测到旧环境 ${ENV_DIR}, 备份为 ${ENV_DIR}.bak$(date +%s)${CEND}"
            mv "${ENV_DIR}" "${ENV_DIR}.bak$(date +%s)"
        fi
        mkdir -p "${ENV_DIR}"
        cp -rf /tmp/gstlenv_src/* "${ENV_DIR}/"
        rm -rf /tmp/gstlenv_src
    else
        # codeload 模式
        cd /tmp && tar zxf "${TMP_TAR}" || { echo -e "${CRED}解压失败${CEND}"; exit 1; }
        if [ -d /tmp/gstlenv_non_docker-main ]; then
            if [ -d "${ENV_DIR}" ] && [ -f "${ENV_DIR}/install.sh" ]; then
                echo -e "${CYELLOW}检测到旧环境 ${ENV_DIR}, 备份为 ${ENV_DIR}.bak$(date +%s)${CEND}"
                mv "${ENV_DIR}" "${ENV_DIR}.bak$(date +%s)"
            fi
            mkdir -p "${ENV_DIR}"
            cp -rf /tmp/gstlenv_non_docker-main/* "${ENV_DIR}/"
            rm -rf /tmp/gstlenv_non_docker-main
        else
            echo -e "${CRED}错误: 解压目录不存在, 部署失败${CEND}"
            exit 1
        fi
    fi
    rm -f "${TMP_TAR}"
    echo -e "${CGREEN}源码已部署: ${ENV_DIR}${CEND}"
}

# ---------- 检查离线组件(可选) ----------
check_offline() {
    # 如果 /root 下存在离线组件压缩包, 提示如何启用离线模式
    local packs=$(ls /root/tlbb离线组件*.zip /root/tlbb离线组件*.tar.gz /root/offline*.tar.gz 2>/dev/null | head -1)
    if [ -n "$packs" ]; then
        echo -e "${CYELLOW}检测到离线组件包: ${packs}${CEND}"
        echo -e "${CYELLOW}如需离线安装, 请先解压到 ${ENV_DIR}/offline-packs/ 后执行: bash ${ENV_DIR}/install.sh --offline${CEND}"
    fi
}

# ============================================================
# 主流程
# ============================================================
brand_banner
download
deploy
check_offline

echo -e "${CGREEN}开始执行环境安装 (install.sh), 请耐心等待...${CEND}"
echo -e "${CYELLOW}提示: 如需指定数据库密码, 可先执行: bash ${ENV_DIR}/install.sh --dbpass 你的密码${CEND}"
cd "${ENV_DIR}" || exit 1

# 透传参数 (--online / --offline / --dbpass xxx / 环境变量)
bash install.sh "$@" | tee -a /root/.tlgame/install.log

echo -e "${CPURPLE}==============================================================${CEND}"
echo -e "${CCYAN}  GS游享网 · 天龙八部万能环境 安装流程结束${CEND}"
echo -e "${CPURPLE}==============================================================${CEND}"
