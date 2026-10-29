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

# comment: 还原数据库
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

if [ $# -ne 2 ]; then
    echo "${CRED}参数不正确，请输入【restore web web.sql】参数1：数据库名，参数2：需要还原的数据库文件的绝对路径 ${CEND}"
    exit 1
else
    if [ $1 != 'web' ] && [ $1 != 'tlbbdb' ]; then
        echo "${CRED}参数1不正确，请输入 【web】 或者 【tlbbdb】 ${CEND}"
        exit 1
    else
        if [ ! -f $2 ]; then
            echo "${CRED}参数2，数据库文件不存在或者路径不正确，请输入正确文件路径。如：【/tlgame/backup/web-2022-05-06.sql】 ${CEND}"
            exit 1
        else
            FILENAME=$(basename $2)
            # 先执行备份 (只备份数据库)
            backup 2
            # 再还原数据库 (原生: 本机 mysql 导入)
            mysql -uroot -p"${TL_MYSQL_PASSWORD}" $1 <$2 2>/dev/null

            if [ $? -eq 0 ]; then
                echo -e "${CSUCCESS} 数据还原成功！！如有疑问可查看【${BACKUP_DIR:-/tlgame/backup}】有还原前的备份，可尝试手动使用工具导入${CEND}"
                exit 0
            else
                echo -e "${GSISSUE}\r\n"
                echo -e "${CRED} 数据还原失败！！${CEND}"
                exit 1
            fi
        fi
    fi
fi
