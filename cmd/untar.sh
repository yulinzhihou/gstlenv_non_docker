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

# comment: 解压tar.gz/zip文件包到指定的目录，并给相应的权限
# 服务端父目录 (/tlgame, TLBB_PATH=/tlgame/tlbb)
TLBB_HOME="${TLBB_HOME:-/tlgame}"
TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"

if [ -f "/root/tlbb.tar.gz" ]; then
    # 备份旧端 -> 删除旧端 -> 解压新端 -> 重命名原压缩包
    tar zcf /root/tlgame-$(date +%Y%m%d%H%I%S)${SUFFIX} ${TLBB_PATH} 2>/dev/null &&
        rm -rf ${TLBB_PATH} &&
        tar zxf /root/tlbb.tar.gz -C ${TLBB_HOME} >/dev/null 2>&1 &&
        mv /root/tlbb.tar.gz /root/$(date +%Y%m%d%H%I%S)-tlbb.tar.gz 2>/dev/null

    echo -e "${CSUCCESS}服务端文件【tlbb.tar.gz】已经解压成功！接下来可以执行【 setini 】进行配置文件写入！${CEND}"
    exit 0
elif [ -f "/root/tlbb.zip" ]; then
    # 备份旧端 -> 删除旧端 -> 解压新端 -> 重命名原压缩包
    tar zcf /root/tlgame-$(date +%Y%m%d%H%I%S)${SUFFIX} ${TLBB_PATH} 2>/dev/null &&
        rm -rf ${TLBB_PATH} &&
        unzip -q /root/tlbb.zip -d ${TLBB_HOME} >/dev/null 2>&1 &&
        mv /root/tlbb.zip /root/$(date +%Y%m%d%H%I%S)-tlbb.zip 2>/dev/null

    echo -e "${CSUCCESS}服务端文件【tlbb.zip】 已经解压成功！，可以执行【 setini 】进行配置文件写入${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}服务端文件不存在，或者位置上传错误，请上传至 [/root] 目录下面${CEND}"
    exit 1
fi
