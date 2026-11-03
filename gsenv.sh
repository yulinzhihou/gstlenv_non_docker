#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 在线一键安装引导 (下载仓库源码部署到 /root/.tlgame, 透传参数执行 install.sh)

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
# 离线组件安装(引导下载源码仍需网络, 完全离线请上传完整源码后运行 install.sh):
#   curl -fsSL https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/gsenv.sh | bash -s -- --offline
#   自动识别 /root/offline-*.tar.gz /root/tlbb离线组件*.zip 并解压到 /root/.tlgame/offline/
#   默认在线; 只有 --offline 或 TLBB_OFFLINE_MODE=1 才使用离线组件, 命令行优先
# ------------------------------------------------------------
# 流程: 检测root -> 展示广告 -> 下载仓库源码 -> 部署到 /root/.tlgame
#       -> 执行 install.sh (透传参数)
# ============================================================

export LC_ALL=C

# ---------- 颜色 ----------
CRED='\033[31m'; CGREEN='\033[32m'; CYELLOW='\033[33m'; CBLUE='\033[34m'; CPURPLE='\033[35m'; CCYAN='\033[36m'; CEND='\033[0m'

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

# ---------- 模式由用户选择, 不由遗留文件决定 ----------
select_install_mode() {
    GSENV_OFFLINE_MODE="${TLBB_OFFLINE_MODE:-0}"
    GSENV_OFFLINE_DIR="${TLBB_OFFLINE_DIR:-${ENV_DIR}/offline}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --online) GSENV_OFFLINE_MODE=0; shift;;
            --offline) GSENV_OFFLINE_MODE=1; shift;;
            --dbpass|--offline-dir)
                [ $# -ge 2 ] || { echo "错误: $1 缺少参数" >&2; return 2; }
                [ "$1" != "--offline-dir" ] || GSENV_OFFLINE_DIR="$2"
                shift 2;;
            *) shift;;
        esac
    done
    case "$GSENV_OFFLINE_MODE" in
        0|1) :;;
        *) echo "错误: TLBB_OFFLINE_MODE 只支持 0 (在线) 或 1 (离线)" >&2; return 2;;
    esac
}

find_offline_archive() {
    local pack
    for pack in /root/tlbb离线组件*.zip /root/tlbb离线组件*.tar.gz /root/offline*.tar.gz /root/*-offline.tar.gz; do
        [ -f "$pack" ] || continue
        printf '%s\n' "$pack"
        return 0
    done
}

# ---------- 仅显式离线模式检查/解压组件 ----------
check_offline() {
    local offline_dir="$GSENV_OFFLINE_DIR" packs
    packs=$(find_offline_archive)
    if [ -n "$packs" ]; then
        echo -e "${CYELLOW}检测到离线组件包: ${packs}${CEND}"
        # 已解压且非空则跳过
        if [ -d "$offline_dir" ] && find "$offline_dir" -mindepth 1 -maxdepth 1 2>/dev/null | grep -q .; then
            echo -e "${CGREEN}离线组件已就绪: ${offline_dir}/${CEND}"
            return 0
        fi
        echo -e "${CYELLOW}自动解压离线组件包到 ${offline_dir}/ ...${CEND}"
        mkdir -p "$offline_dir" || return 1
        case "$packs" in
            *.tar.gz|*.tgz)
                tar zxf "$packs" -C "$offline_dir" 2>/dev/null || \
                    { echo -e "${CRED}解压失败: $packs (请手动解压后重试)${CEND}"; return 1; } ;;
            *.zip)
                if command -v unzip >/dev/null 2>&1; then
                    unzip -q -o "$packs" -d "$offline_dir" 2>/dev/null || \
                        { echo -e "${CRED}解压失败: $packs (请手动解压后重试)${CEND}"; return 1; }
                else
                    echo -e "${CRED}未安装 unzip, 无法自动解压 ${packs}${CEND}"
                    echo -e "${CYELLOW}请手动解压到: ${offline_dir}/${CEND}"
                    return 1
                fi ;;
            *)
                echo -e "${CRED}不支持的离线包格式: $packs${CEND}"
                return 1 ;;
        esac
        # 兼容包内带 offline/ 顶层目录的情况
        if [ -d "${offline_dir}/offline" ]; then
            mv "${offline_dir}/offline"/* "${offline_dir}/" 2>/dev/null
            rmdir "${offline_dir}/offline" 2>/dev/null || true
        fi
        if find "$offline_dir" -mindepth 1 -maxdepth 1 2>/dev/null | grep -q .; then
            echo -e "${CGREEN}离线组件已就绪: ${offline_dir}/${CEND}"
        else
            echo -e "${CRED}解压后 offline/ 为空, 请检查离线包内容${CEND}"
            return 1
        fi
    fi
    return 0
}

# ============================================================
# 主流程
# ============================================================
gsenv_main() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${CRED}错误: 在线安装必须使用 ROOT 用户执行!${CEND}"
        echo -e "${CYELLOW}请先执行: sudo su - 切换到 root 后再运行${CEND}"
        return 1
    fi
    select_install_mode "$@" || return $?
    brand_banner
    download
    deploy
    cd "${ENV_DIR}" || return 1

    local mode_arg=--online
    if [ "$GSENV_OFFLINE_MODE" = "1" ]; then
        mode_arg=--offline
        check_offline || return 1
        echo -e "${CGREEN}安装模式: [离线] (用户指定)${CEND}"
    else
        echo -e "${CGREEN}安装模式: [在线] (不自动解压或启用 /root 下的离线包)${CEND}"
    fi

    echo -e "${CGREEN}开始执行环境安装 (install.sh), 请耐心等待...${CEND}"
    echo -e "${CYELLOW}提示: 如需指定数据库密码, 使用 --dbpass 参数${CEND}"
    bash install.sh "$mode_arg" "$@" 2>&1 | tee -a "${ENV_DIR}/install.log"
    local install_status=${PIPESTATUS[0]}
    if [ "$install_status" -ne 0 ]; then
        echo -e "${CRED}安装未完成 (退出码 ${install_status}), 日志: ${ENV_DIR}/install.log${CEND}"
        return "$install_status"
    fi

    echo -e "${CPURPLE}==============================================================${CEND}"
    echo -e "${CCYAN}  GS游享网 · 天龙八部万能环境 安装流程结束${CEND}"
    echo -e "${CPURPLE}==============================================================${CEND}"
}

# BASH_SOURCE is empty when invoked through curl | bash.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    gsenv_main "$@"
fi
