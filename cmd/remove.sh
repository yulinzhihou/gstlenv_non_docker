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

# comment: 移除整个环境，相当于重装系统 (原生: 停服/移除命令/迁移数据目录/删除配置)
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

TLBB_HOME="${TLBB_HOME:-/tlgame}"
GS_WHOLE_PATH="${GS_WHOLE_PATH:-/root/.gs/.env}"
GS_PROJECT="${GS_PROJECT:-/root/.tlgame}"

main() {
    for ((time = 5; time >= 0; time--)); do
        echo -ne "\r在准备正行移除环境操作！！，剩余 ${CRED}$time${CEND} 秒，可以在计时结束前，按 CTRL+C 退出！"
        sleep 1
    done
    echo
    while :; do
        echo -e "${CYELLOW}请输入 [y/n] 是否确认移除环境, 默认[n]取消${CEND}"
        read -e -p "${CYELLOW}请输入确认信息 [y/n]:${CEND} " IS_MODIFY
        IS_MODIFY=${IS_MODIFY:-'n'}
        if [[ ! ${IS_MODIFY} =~ ^[y,n]$ ]]; then
            echo "${CWARNING}输入错误! 请输入 y 或者 n ${CEND}"
        else
            if [ "${IS_MODIFY}" == 'y' ]; then
                echo -e "${CYELLOW}正在移除环境……${CEND}"
                # 关闭服务端
                close >/dev/null 2>&1
                # 移除全局命令 (原生: gs 原命令名 + gsctl + color)
                for name in untar setini runtlbb runtop setconfig setpoint setvalid gslog rmlog link gsfix gsbak swap change close restart remove backup reset restore delbak logbak curgs gs gstl step upcmd upgm upow transfer rebuild gsctl color; do
                    rm -f /usr/local/bin/${name} 2>/dev/null
                done
                # 删除环境配置
                rm -rf /root/.gs 2>/dev/null
                # 迁移数据目录 (保留数据, 可手动恢复)
                if [ -d ${TLBB_HOME} ]; then
                    mv ${TLBB_HOME} ${TLBB_HOME}-$(date +%Y%m%d%H%I%S) 2>/dev/null
                fi
                # 移除 crontab 中的备份任务
                crontab -l 2>/dev/null | grep -v "/usr/local/bin/backup" | grep -v "/usr/local/bin/delbak" | grep -v "/usr/local/bin/logbak" | crontab - 2>/dev/null
                echo -e "${CSUCCESS}环境移除成功！如需重新安装，请重新下载环境包并执行安装！${CEND}"
                exit 0
            else
                echo -e "${CYELLOW}你已经取消本次操作${CEND}"
                exit 0
            fi
            break
        fi
    done
}

main
