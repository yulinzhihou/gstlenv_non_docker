#!/bin/bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: Debian 系一键安装入口 (自动识别 Debian 10~18)

# TLBB 环境一键安装 - Debian 系 (Debian (10~18 自动识别))
# 用法: bash debian.sh
# 说明: 自动识别 Ubuntu/Debian 版本代号, 自动选择国内源/归档源
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/detect.sh"
source "$SCRIPT_DIR/modules/debian/install.sh"
check_root
check_arch
detect_system
detect_cloud
SYS_FAMILY="debian"
TLBB_OFFLINE_DIR="$SCRIPT_DIR/offline"
print_sysinfo
deb_install
echo ""
echo "+--------------------------------------------------------------+"
echo "| TLBB 环境安装结束 | 数据库 root / ${TLBB_DB_PASS}              |"
echo "+--------------------------------------------------------------+"

