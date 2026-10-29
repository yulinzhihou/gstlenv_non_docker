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

# comment: 进入相应的服务 (原生: 本机直连/直接进入目录)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "${CRED}参数不能为空,请输入 【mysql】、【server】、【nginx】、【redis】、【php】 中的任意一个${CEND}"
    exit 1
else
    case $1 in
    'mysql')
        if command -v mysql >/dev/null 2>&1; then
            echo -e "${CSUCCESS}进入 MySQL 数据库 (原生直连), 输入 exit 退出${CEND}"
            mysql -uroot -p"${TL_MYSQL_PASSWORD}"
        else
            echo -e "${CRED}本机未安装 mysql 客户端${CEND}"
            exit 1
        fi
        ;;
    'server')
        echo -e "${CSUCCESS}进入服务端目录 ${TLBB_PATH:-/tlgame/tlbb}, 输入 exit 退出${CEND}"
        cd ${TLBB_PATH:-/tlgame/tlbb} && bash
        ;;
    'nginx')
        if command -v nginx >/dev/null 2>&1; then
            echo -e "${CSUCCESS}进入 Nginx 交互: 输入 nginx -s reload 重载, 输入 exit 退出${CEND}"
            bash
        else
            echo -e "${CRED}原生环境未单独安装 nginx (网站可直接使用 Apache/其他服务)${CEND}"
            exit 1
        fi
        ;;
    'redis')
        if command -v redis-cli >/dev/null 2>&1; then
            echo -e "${CSUCCESS}进入 Redis 交互: 输入 auth ${REDIS_PASSWORD} 认证, 输入 exit 退出${CEND}"
            redis-cli
        else
            echo -e "${CRED}原生环境未安装 redis, 可执行【setini】写入配置供 GM 工具使用${CEND}"
            exit 1
        fi
        ;;
    'php')
        if command -v php >/dev/null 2>&1; then
            echo -e "${CSUCCESS}进入 PHP 交互, 输入 exit 退出${CEND}"
            php -a
        else
            echo -e "${CRED}原生环境未安装 php${CEND}"
            exit 1
        fi
        ;;
    *)
        echo "${CRED}参数不正确, 请输入 【mysql】、【server】、【nginx】、【redis】、【php】 中的任意一个${CEND}"
        exit 1
        ;;
    esac
fi
