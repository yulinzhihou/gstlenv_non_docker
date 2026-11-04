#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: GS游享环境命令统一入口 (原生版, 替代 tl_* 前缀)

# ============================================================
# gsctl - GS游享环境命令统一入口 (原生版, 替代 tl_* 前缀)
# 用法:
#   gsctl                   查看用法
#   gsctl <命令> [参数...]  执行对应命令, 如: gsctl untar / gsctl setconfig
#   gsctl gs 01             查看并执行 gs 帮助菜单
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ -f /root/.gs/.env ] && . /root/.gs/.env

if [ $# -eq 0 ]; then
    echo "${CYELLOW}gsctl - GS游享环境命令统一入口${CEND}"
    echo "用法: gsctl <命令> [参数...]"
    echo "示例:"
    echo "  gsctl untar              解压服务端"
    echo "  gsctl setini             配置服务端 ini"
    echo "  gsctl runtlbb            开启服务端"
    echo "  gsctl runtop             按 run.sh 实时监控开服进程 (q 退出)"
    echo "  gsctl setconfig          重新设置配置参数"
    echo "  gsctl gs 01              查看 gs 命令帮助并执行"
    echo "查看全部命令帮助: gs"
    exit 0
fi

CMD="$1"; shift
if [ -x "/usr/local/bin/$CMD" ]; then
    exec "/usr/local/bin/$CMD" "$@"
else
    echo "${CRED}错误: 未知命令 [${CMD}] !${CEND}"
    echo "${CYELLOW}请使用 gsctl gs 查看全部命令帮助, 或直接输入 gs 获取命令菜单${CEND}"
    exit 1
fi
