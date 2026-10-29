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

# comment: 手动执行备份数据库功能和打包服务端
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TIME="[$(date +%Y_%m_%d_%H_%M_%S)]"
FILENAME="$(date +%Y-%m-%d)"
FILEPATH="${BACKUP_DIR:-/tlgame/backup}/"
TLBB_HOME="${TLBB_HOME:-/tlgame}"
LOG_FILE="backup-${FILENAME}.log"
# 当前在使用的数据库密码
TL_MYSQL_PASSWORD_CURRENT="${TL_MYSQL_PASSWORD}"

# 检测
if [ ! -d ${FILEPATH} ]; then
    mkdir -p ${FILEPATH}
fi

backup_tlbb() {
    echo -e "${CYELLOW}正在备份服务端版本目录，请稍等……${CEND}\r\n"
    # 备份服务端
    cd ${TLBB_HOME} && tar zcf tlbb-${FILENAME}.tar.gz tlbb 2>/dev/null &&
        mv tlbb-*.tar.gz ${FILEPATH}
    # 判断是否备份成功
    if [ $? -eq 0 ]; then
        echo -ne "${CSUCCESS}$(date '+%Y-%m-%d-%H-%M-%S')\ttlbb-${FILENAME}.tar.gz\t备份成功 ！！！${CEND}\r\n" | tee -a ${FILEPATH}${LOG_FILE}
    else
        echo -ne "${CRED}$(date '+%Y-%m-%d-%H-%M-%S')\ttlbb-${FILENAME}.tar.gz\t备份失败${CEND}\r\n" | tee -a ${FILEPATH}${LOG_FILE}
    fi
}

backup_mysql() {
    echo -e "${CYELLOW}正在备份数据库，请稍等……${CEND}\r\n"
    # 原生: 本机 mysqldump (web 库 + tlbbdb 库)
    if ! mysqladmin ping >/dev/null 2>&1; then
        echo -e "${CRED}数据库未运行，跳过数据库备份！${CEND}"
        return 1
    fi
    DATE_FILENAME=$(date "+%Y%m%d%H%M%S")
    WEB_TBL=$(mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -N -e "use web; show tables;" 2>/dev/null | wc -l)
    TLBBDB_TBL=$(mysql -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" -N -e "use tlbbdb; show tables;" 2>/dev/null | wc -l)
    if [ ${WEB_TBL:-0} -gt 1 ]; then
        mysqldump -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" web >${FILEPATH}web-${DATE_FILENAME}.sql 2>/dev/null &&
            echo -ne "${CSUCCESS}$(date '+%Y-%m-%d-%H-%M-%S')\tweb-${DATE_FILENAME}.sql\t备份成功 ！！！${CEND}\r\n" | tee -a ${FILEPATH}${LOG_FILE} ||
            echo -ne "${CRED}$(date '+%Y-%m-%d-%H-%M-%S')\tweb-${DATE_FILENAME}.sql\t备份失败${CEND}\r\n" | tee -a ${FILEPATH}${LOG_FILE}
    fi
    if [ ${TLBBDB_TBL:-0} -gt 1 ]; then
        mysqldump -uroot -p"${TL_MYSQL_PASSWORD_CURRENT}" --opt -R tlbbdb >${FILEPATH}tlbbdb-${DATE_FILENAME}.sql 2>/dev/null &&
            echo -ne "${CSUCCESS}$(date '+%Y-%m-%d-%H-%M-%S')\ttlbbdb-${DATE_FILENAME}.sql\t备份成功 ！！！${CEND}\r\n" | tee -a ${FILEPATH}${LOG_FILE} ||
            echo -ne "${CRED}$(date '+%Y-%m-%d-%H-%M-%S')\ttlbbdb-${DATE_FILENAME}.sql\t备份失败${CEND}\r\n" | tee -a ${FILEPATH}${LOG_FILE}
    fi
}

# 根据输入判断备份类型
if [ $# -eq 0 ]; then
    while :; do
        echo
        echo -e "${CYELLOW}请选择需要备份的类型，0=备份版本+数据库，1=只备份版本，2=只备份数据库。默认为[0]备份所有.备份目录[${FILEPATH}]${CEND}"
        read -e -p "${CYELLOW}请输入[0]=备份版本+数据库,[1]=只备份版本,[2]=只备份数据库[0、1、2](默认: 0):${CEND} " IS_MODIFY
        IS_MODIFY=${IS_MODIFY:-'0'}
        case ${IS_MODIFY} in
        0)
            backup_tlbb &&
                backup_mysql
            break
            ;;
        1)
            backup_tlbb
            break
            ;;
        2)
            backup_mysql
            break
            ;;
        *)
            echo -e "${CWARNING}输入错误! 请输入 0-2 ${CEND}"
            break
            ;;
        esac
    done
else
    if [ $1 == 'all' ] || [ $1 -eq 0 ]; then
        backup_tlbb && backup_mysql
    elif [ $1 -eq 1 ]; then
        backup_tlbb
    elif [ $1 -eq 2 ]; then
        backup_mysql
    else
        echo -e "${CRED}${TIME}参数错误！backup 后面跟 all,0,1,2这4个参数中的任意一个${CEND}" | tee -a ${GS_PROJECT}/gs.log
        exit 1
    fi
fi

if [ $? -eq 0 ]; then
    echo -e "${CSUCCESS}${TIME}已经成功备份完成，备份文件在 [${FILEPATH}] 目录下${CEND}" | tee -a ${GS_PROJECT}/gs.log
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}${TIME}备份失败！${CEND}" | tee -a ${GS_PROJECT}/gs.log
    exit 1
fi
