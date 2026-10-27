#!/bin/bash
# ============================================================
# tl - TLBB 原生环境命令总菜单 (参考 gstlenv 的 gs 命令)
# 用法: tl [命令名]  如: tl untar / tl runtlbb
# ============================================================
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
[ "$(id -u)" != "0" ] && { echo "错误: 必须使用 root 用户"; exit 1; }

show_help() {
cat <<EOF
==========================================================
  GS游享网 · 天龙八部万能环境 (gsgameshare.com)
  TLBB 原生环境管理命令 (安装于 /usr/local/bin/tl_*)
  用法: tl [命令]   或直接执行 tl_<命令>
==========================================================
 01:untar      解压服务端 (tlbb.tar.gz/tlbb.zip -> /home/tlbb)
 02:setini     配置服务端 ini 文件
 03:runtlbb    开启服务端
 04:runtop     查看开服状态 (进程/端口)
 05:close      关服
 06:restart    重启服务端
 07:swap       增加虚拟内存
 08:backup     备份数据库 (mysqldump)
 09:restore    还原数据库
 10:reset      删档并重导 tlbbdb/web 库
 11:setvalid   解/封号
 12:setpoint   设置默认充值点数
 13:curgs      查看当前环境配置
 14:change     换端 (备份旧端并解压新端)
 15:rebuild    重构环境 (重跑 install.sh)
 16:remove     卸载环境
 17:delbak     删除备份文件
 18:logbak     备份日志文件
 19:gslog      查看服务端日志
 20:rmlog      清理日志
 0:q           退出
==========================================================
EOF
}

cmd="$1"
[ -z "$cmd" ] && { show_help; exit 0; }
case "$cmd" in
    untar)    tl_untar;;
    setini)   tl_setini;;
    runtlbb)  tl_runtlbb;;
    runtop)   tl_runtop;;
    close)    tl_close;;
    restart)  tl_restart;;
    swap)     tl_swap;;
    backup)   tl_backup;;
    restore)  tl_restore;;
    reset)    tl_reset;;
    setvalid) tl_setvalid;;
    setpoint) tl_setpoint;;
    curgs)    tl_curgs;;
    change)   tl_change;;
    rebuild)  tl_rebuild;;
    remove)   tl_remove;;
    delbak)   tl_delbak;;
    logbak)   tl_logbak;;
    gslog)    tl_gslog;;
    rmlog)    tl_rmlog;;
    q|exit)   exit 0;;
    *)        echo "未知命令: $cmd"; show_help;;
esac
