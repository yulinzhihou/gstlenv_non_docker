#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Forum:  https://gsgamesahre.com
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 天龙八部服务端环境万能安装器 (非 Docker 原生版), 支持 RHEL/Debian/Ubuntu/Fedora/OpenEuler, 在线/离线双模式
# comment: 帮助命令 (交互与 gstlenv gs.sh 一致)

# 设置字符编码，确保中文正常显示
{
    export LANG=C.UTF-8 2>/dev/null || export LANG=en_US.UTF-8 2>/dev/null || export LANG=POSIX 2>/dev/null || true
    export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX 2>/dev/null || true
} 2>/dev/null
# 引入全局参数
[ -f /root/.gs/.env ] && . /root/.gs/.env
# 颜色代码
[ -f /usr/local/bin/color ] && . /usr/local/bin/color

[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

show_help() {
cat <<EFF
${CYELLOW}###########################################
#                                         
#    GS游享网 · 天龙八部万能环境           
#    gs 命令帮助 | 出品: gsgameshare.com   
#                                         
#    此命令只获取命令帮助, 不会直接执行   
#                                         
#    用法1: gs 01  获取第一个命令帮助文档 
#    用法2: gs 1  获取第一个命令帮助文档  
#    用法3: gs untar 获取第一个命令帮助文档
#    统一入口: gsctl <命令> [参数...]      
#                                         
###########################################
#    01:untar      解压服务端             
#    02:setini     配置ini文件            
#    03:runtlbb    开启服务端             
#    04:runtop     实时监控开服进程
#    05:link       连接服务端目录         
#    06:swap       增加虚拟缓存           
#    07:rebuild    重构环境               
#    08:remove     移除环境               
#    09:setconfig  设置配置参数           
#    10:change     换端                   
#    11:restart    重启环境/服务          
#    12:gsbak      定时备份数据           
#    13:upcmd      在线更新全局命令
#    14:upgm       配置在线GM网站         
#    15:upow       配置开服网站           
#    16:step       分步调试开服           
#    17:gstl       环境安装初始化         
#    18:backup     手动备份数据库         
#    19:close      关服                   
#    20:gslog      查看日志               
#    21:rmlog      删除日志               
#    22:curgs      查看配置               
#    23:setpoint   设置默认充值点数       
#    24:reset      删档数据库             
#    25:setvalid   解/封号                
#    26:restore    还原数据库             
#    27:delbak     删除备份文件           
#    28:gsfix      修复环境安装           
#    29:logbak     定时备份日志文件       
#    30:mysql-user 设置MySQL授权用户/主机/密码(默认0.0.0.0/0=所有机器)
#    31:mysql-lock 关闭所有机器连接,仅保留root@127.0.0.1+root@localhost
#    0:q 退出,或者按 CTRL+C               
###########################################${CEND}
EFF
}

# 命令执行/帮助分发 (对齐 gstlenv: 打印帮助后直接执行)
CMD_MAP="untar setini runtlbb runtop link swap rebuild remove setconfig change restart gsbak upcmd upgm upow step gstl backup close gslog rmlog curgs setpoint reset setvalid restore delbak gsfix logbak mysql-user mysql-lock"

run_or_help() {
    local name="$1"
    echo ""
    echo "${CGREEN}==> 命令: ${CRED}${name}${CEND} ${CGREEN}(执行中)${CEND}"
    echo ""
    case "$name" in
        untar)    echo "${CGREEN}untar: 解压服务端压缩包(tlbb.tar.gz/tlbb.zip), 需上传到 /root${CEND}"; untar;;
        setini)   echo "${CGREEN}setini: 统一 /tlgame 路径并检查 run.sh，再写入3个ini、数据库连接和 Billing 配置${CEND}"; setini;;
        runtlbb)  echo "${CGREEN}runtlbb: 运行一键服务端命令(调用 run.sh)${CEND}"; runtlbb;;
        runtop)   echo "${CGREEN}runtop: 按 run.sh 实时监控进程(CPU/内存/PID), q 退出; runtop --once 输出快照${CEND}"; runtop;;
        link)     echo "${CGREEN}link: 进入服务端目录命令行${CEND}"; link;;
        swap)     echo "${CGREEN}swap: 增加虚拟缓存${CEND}"; swap;;
        rebuild)  echo "${CGREEN}rebuild: 重构环境${CEND}"; rebuild;;
        remove)   echo "${CGREEN}remove: 移除环境${CEND}"; remove;;
        setconfig) echo "${CGREEN}setconfig: 重新设置配置参数(端口/密码)${CEND}"; setconfig;;
        change)   echo "${CGREEN}change: 换端${CEND}"; change;;
        restart)  echo "${CGREEN}restart: 重启环境/服务${CEND}"; restart;;
        gsbak)    echo "${CGREEN}gsbak: 定时备份数据${CEND}"; gsbak;;
        upcmd)    echo "${CGREEN}upcmd: 在线下载并校验更新全局命令${CEND}"; upcmd;;
        upgm)     echo "${CGREEN}upgm: 配置在线GM网站${CEND}"; upgm;;
        upow)     echo "${CGREEN}upow: 配置开服网站${CEND}"; upow;;
        step)     echo "${CGREEN}step: 按实际程序分步前台调试；step --list 查看编号，step --check 检查路径，step N 启动一个程序${CEND}"; step;;
        gstl)     echo "${CGREEN}gstl: 环境安装初始化${CEND}"; gstl;;
        backup)   echo "${CGREEN}backup: 手动备份数据库${CEND}"; backup;;
        close)    echo "${CGREEN}close: 关服${CEND}"; close;;
        gslog)    echo "${CGREEN}gslog: 查看日志${CEND}"; gslog;;
        rmlog)    echo "${CGREEN}rmlog: 删除日志${CEND}"; rmlog;;
        curgs)    echo "${CGREEN}curgs: 查看配置${CEND}"; curgs;;
        setpoint) echo "${CGREEN}setpoint: 设置默认充值点数${CEND}"; setpoint;;
        reset)    echo "${CGREEN}reset: 删档数据库${CEND}"; reset;;
        setvalid) echo "${CGREEN}setvalid: 解/封号${CEND}"; setvalid;;
        restore)  echo "${CGREEN}restore: 还原数据库${CEND}"; restore;;
        delbak)   echo "${CGREEN}delbak: 删除备份文件${CEND}"; delbak;;
        gsfix)    echo "${CGREEN}gsfix: 修复环境安装${CEND}"; gsfix;;
        logbak)   echo "${CGREEN}logbak: 定时备份日志文件${CEND}"; logbak;;
        mysql-user) echo "${CGREEN}mysql-user: 设置MySQL授权用户/主机/密码 (用法: mysql-user [用户名] [密码] [主机], 主机默认 0.0.0.0/0=所有机器)${CEND}"; mysql-user;;
        mysql-lock) echo "${CGREEN}mysql-lock: 关闭所有机器连接, 仅保留 root@127.0.0.1 与 root@localhost${CEND}"; mysql-lock;;
        *) echo "${CRED}未知命令: $name${CEND}"; return 1;;
    esac
}

if [ $# -eq 0 ]; then
    show_help
else
    case "$1" in
        0|q|Q) exit 0;;
        [0-9]*)
            # 数字序号 -> 命令名
            n=$((10#$1))
            if [ $n -ge 1 ] && [ $n -le 31 ]; then
                cmdname=$(echo "$CMD_MAP" | awk -v i="$n" '{print $i}')
                run_or_help "$cmdname"
            else
                echo "${CRED}序号无效(1~29)${CEND}"; exit 1
            fi
            ;;
        *)
            run_or_help "$1"
            ;;
    esac
fi
