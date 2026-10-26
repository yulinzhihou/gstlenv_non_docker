#!/bin/bash
# ============================================================
# transfer - 重新构建环境版本 (参考 gstlenv transfer.sh, 原生版)
# 原生环境按本机系统直接构建, 版本选择对应: 引擎类型/数据库版本
# 用法:
#   transfer          交互式选择环境版本
#   transfer 1|2|3|4  指定版本直接构建
# 1=Centos6+Mysql5.1(老品种) 2=Centos7+Mysql5.1 3=Centos7+Mysql5.7 4=Centos9+Mysql8.0
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"
BACKUP_DIR="$TLBB_HOME/backup"
mkdir -p "$BACKUP_DIR"

# 检测当前系统对应版本号
detect_current_index() {
    local ver=""
    [ -f /etc/os-release ] && ver=$(grep -E '^(VERSION_ID|VERSION)=' /etc/os-release 2>/dev/null | head -1 | tr -d '"' | cut -d= -f2)
    case "$ver" in
        6*) echo 1;;
        7*) echo 2;;
        8*|9*) echo 4;;
        *) echo 2;;
    esac
}
DEFAULT_ENV_INDEX=$(detect_current_index)

# 备份数据库+版本 (对齐 gstlenv)
backup_data() {
    echo "正在备份版本数据请稍候......"
    if [ -d "$TLBB_HOME/tlbb" ]; then
        tar zcf "$BACKUP_DIR/tlbb-setconfig-backup.tar.gz" -C "$TLBB_HOME" tlbb 2>/dev/null && \
            echo "${CSUCCESS}版本备份完成: $BACKUP_DIR/tlbb-setconfig-backup.tar.gz${CEND}"
    fi
    if command -v backup >/dev/null 2>&1; then backup; fi
}

# 还原数据
restore_data() {
    if [ -f "$BACKUP_DIR/tlbb-setconfig-backup.tar.gz" ]; then
        tar zxf "$BACKUP_DIR/tlbb-setconfig-backup.tar.gz" -C "$TLBB_HOME" 2>/dev/null
        mv "$BACKUP_DIR/tlbb-setconfig-backup.tar.gz" "$BACKUP_DIR/" 2>/dev/null
        echo "${CSUCCESS}版本已还原${CEND}"
    fi
}

# 选择版本
switch_env() {
    local env_index="$1"
    if [ -z "$env_index" ]; then
        cat <<EOF
${CYELLOW}
※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※
◎           
◎  TLBB 原生服务器环境 transfer
◎           
◎  编号1：Centos 6 + Mysql5.1 (默认)  ---> （老品种, 没有改引擎和数据库）
◎  编号2：Centos 7 + Mysql5.1      ---> （老品种, 没有改引擎和数据库）
◎  编号3：Centos 7 + Mysql5.7      ---> (大河马引擎, 大背包, 逍遥子引擎, 有改引擎和数据库的)
◎  编号4：Centos 9 + Mysql8.0      ---> (源端64位引擎专用)
◎
※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※※
${CEND}
EOF
        read -e -p "请输入你需要安装的环境编号【默认不输入则为1, 直接回车即可】(默认: ${DEFAULT_ENV_INDEX}): " env_index
        env_index=${env_index:-${DEFAULT_ENV_INDEX}}
    fi
    case "${env_index}" in
        '01'|'1') echo "${CYELLOW}选择: Centos 6 + Mysql5.1 (老品种, 无引擎改造)${CEND}";;
        '02'|'2') echo "${CYELLOW}选择: Centos 7 + Mysql5.1 (老品种, 无引擎改造)${CEND}";;
        '03'|'3') echo "${CYELLOW}选择: Centos 7 + Mysql5.7 (大河马/大背包/逍遥子引擎)${CEND}";;
        '04'|'4') echo "${CYELLOW}选择: Centos 9 + Mysql8.0 (源端64位引擎专用)${CEND}";;
        *) echo "${CWARNING}输入的环境编号无效, 使用默认配置${CEND}";;
    esac
    echo "${CYELLOW}本机为原生环境, 系统/数据库版本由当前 Linux 发行版决定${CEND}"
    echo "${CYELLOW}提示: 如需切换引擎类型, 请将对应服务端上传后执行 【 change 】 换端${CEND}"
}

ENV_INDEX="$1"
echo ""
for ((time=5; time>=0; time--)); do
    echo -ne "\r在准备构建环境版本!! 剩余 ${CRED}$time${CEND} 秒, 可以在计时结束前, 按 CTRL+C 退出!"
    sleep 1
done
echo -ne "\r\n"
echo -ne "${CYELLOW}正在重构, 数据不会清除......${CEND}\r\n"

# 重构前备份
backup_data || { echo "${CRED}备份失败!${CEND}"; exit 1; }
# 停服
if command -v close >/dev/null 2>&1; then close; fi
# 切换环境
switch_env "$ENV_INDEX"
# 还原
restore_data

echo ""
echo "${CSUCCESS}环境已经重构成功, 请上传服务端到指定位置, 然后再开服操作!! 可以重新上传服务端进行【untar】【setini】【runtlbb】进行开服操作!!${CEND}"
exit 0
