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

# comment: 查看当前环境配置
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

# 展示环境配置信息 (对齐 gstlenv curgs)
show_config() {
    echo "=============================================================="
    echo "  GS游戏享网 | 非 Docker 原生版 (gstlenv 命令体系)"
    echo "  项目地址: https://github.com/yulinzhihou/gstlenv"
    echo "             https://gitee.com/yulinzhihou/gstlenv"
    echo "--------------------------------------------------------------"
    echo "  版本信息    : v2.8.28 (与 gstlenv 命令/版本一致)"
    echo "  服务端路径  : ${TLBB_PATH:-/tlgame/tlbb}"
    echo "  备份目录    : ${BACKUP_DIR:-/tlgame/backup}"
    echo "  运行模式    : IS_DLQ=${IS_DLQ:-0} (0=单L机验证, 1=W机验证+L机)"
    echo "  Billing验证 : ${BILLING_SERVER_IPADDR:-127.0.0.1}:${BILLING_PORT:-21818}"
    echo "  MySQL 端口  : ${TL_MYSQL_PORT:-3306}"
    echo "  登录端口    : ${LOGIN_PORT:-13580}"
    echo "  游戏端口    : ${SERVER_PORT:-15680}"
    echo "  网站端口    : ${WEB_PORT:-51888} / ${WEB_HTTPS_PORT:-51443}"
    echo "  GM网站端口  : ${WEB_GM_PORT:-61888}"
    echo "  数据库账号  : root / ${TL_MYSQL_PASSWORD}"
    echo "  游戏账号    : ${LOGIN_USER_NAME:-gsgameshare} / ${LOGIN_PASSWORD:-gsgameshare.com}"
    echo "  GM 私钥     : ${PRIVATE_KEY:-Gsgameshare.com2025}"
    echo "  Redis 密码  : ${REDIS_PASSWORD:-gsgameshare.com}"
    echo "=============================================================="
    echo "  技术交流群: 902281567 | 电报群: https://t.me/gstlenv"
    echo "  作者: GS游享网 (gsgameshare.com)  仅供学习研究, 24小时内删除"
    echo "=============================================================="
}

show_config
exit 0
