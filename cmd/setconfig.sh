#!/bin/bash
# ============================================================
# setconfig - 重新设置配置参数 (参考 gstlenv setconfig.sh, 原生版)
# 修改: 数据库密码/端口, 登录端口, 游戏端口, 网站端口, GM端口, 验证模式
# 说明: 执行完成后需要重启数据库与服务端使配置生效
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] || { echo "${CRED}环境未安装, 请先执行 gstl / install.sh${CEND}"; exit 1; }
ENV_FILE=/root/.tlbb/tlbb.env

# 从当前 env 读取旧值 (默认值对齐 gstlenv env.sample)
. "$ENV_FILE"
TLBB_DB_PASS="${TLBB_DB_PASS:-123456}"
TLBB_DB_PORT="${TLBB_DB_PORT:-3306}"
TLBB_LOGIN_PORT="${TLBB_LOGIN_PORT:-13580}"
TLBB_GAME_PORT="${TLBB_GAME_PORT:-15680}"
TLBB_WEB_PORT="${TLBB_WEB_PORT:-51888}"
TLBB_GM_PORT="${TLBB_GM_PORT:-61888}"
TLBB_BILLING_PORT="${TLBB_BILLING_PORT:-21818}"

# 修改 env 变量
set_env() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >>"$ENV_FILE"
    fi
}

# 交互式修改 (对齐 gstlenv: 询问是否修改)
modify_value() {
    local key="$1" desc="$2" cur="$3" default="$4" valid="$5"
    local is_modify=""
    echo ""
    read -e -p "当前【${desc}】为: [${cur}], 是否需要修改 [y/n](默认: n): " is_modify
    is_modify=$(echo "${is_modify:-n}" | tr 'A-Z' 'a-z')
    [ "$is_modify" != "y" ] && return 0
    local new_val=""
    read -e -p "请输入【${desc}】(默认: ${default}): " new_val
    new_val=${new_val:-$default}
    # 端口校验
    if [ "$valid" = "port" ]; then
        if ! [[ "$new_val" =~ ^[0-9]+$ ]] || [ "$new_val" -lt 1 ] || [ "$new_val" -gt 65535 ]; then
            echo "${CRED}输入错误! 端口范围: 1~65535${CEND}"
            return 1
        fi
    fi
    if [ "$valid" = "pass" ]; then
        if [ ${#new_val} -lt 5 ]; then
            echo "${CRED}密码最少要6个字符!${CEND}"
            return 1
        fi
    fi
    set_env "$key" "$new_val"
    echo "${CSUCCESS}【${desc}】已更新为: ${new_val}${CEND}"
    # 记录最新值供后续密码修改
    case "$key" in
        TLBB_DB_PASS) NEW_DB_PASS="$new_val";;
        TLBB_DB_PORT) NEW_DB_PORT="$new_val";;
    esac
}

# 修改数据库密码 (兼容 MySQL 5.1/5.7/8.0)
change_db_password() {
    [ -n "$NEW_DB_PASS" ] || return 0
    local old="${TLBB_DB_PASS}"
    echo "${CYELLOW}正在修改数据库密码 ${old} -> ${NEW_DB_PASS}...${CEND}"
    # MySQL 5.7+/8.0: 用 ALTER USER + native 认证
    mysql -uroot -p"$old" -e \
        "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${NEW_DB_PASS}'; ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${NEW_DB_PASS}'; FLUSH PRIVILEGES;" >/dev/null 2>&1 && \
        echo "${CSUCCESS}数据库密码修改成功! (ALTER USER)${CEND}" || \
    # 老 MySQL (5.1/5.5/5.6): 用 SET PASSWORD
    mysql -uroot -p"$old" -e \
        "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${NEW_DB_PASS}'); SET PASSWORD FOR 'root'@'%' = PASSWORD('${NEW_DB_PASS}'); FLUSH PRIVILEGES;" >/dev/null 2>&1 && \
        echo "${CSUCCESS}数据库密码修改成功! (SET PASSWORD)${CEND}" || \
        echo "${CWARNING}数据库密码修改失败, 请手动执行 ALTER USER 或核对旧密码${CEND}"
}

echo "${CMAGENTA}即将设置服务器环境配置, 请仔细!! 执行完成后需重启数据库与服务端生效${CEND}"
echo "${CYELLOW}按 CTRL+C 可随时退出${CEND}"

# 验证模式 (0=单L机验证, 1=W机验证+L机)
echo ""
echo "${CYELLOW}0=单L机验证(Linux服务器做验证机器, 只需一台服务器)${CEND}"
echo "${CYELLOW}1=W机验证+L机(Windows服务器做验证机器, L机不要开验证服务)${CEND}"
read -e -p "当前【服务器验证模式】为: [${TLBB_IS_DLQ:-0}], 是否需要修改 [y/n](默认: n): " is_modify
is_modify=$(echo "${is_modify:-n}" | tr 'A-Z' 'a-z')
if [ "$is_modify" = "y" ]; then
    read -e -p "请输入【验证模式 0/1】(默认: 0): " new_dlq
    new_dlq=${new_dlq:-0}
    case "$new_dlq" in
        0|1) set_env "TLBB_IS_DLQ" "$new_dlq"; echo "${CSUCCESS}验证模式已更新为: $new_dlq${CEND}";;
        *) echo "${CRED}输入错误! 仅支持 0 或 1${CEND}";;
    esac
fi

modify_value TLBB_DB_PASS     "数据库密码"   "$TLBB_DB_PASS"     "123456"   "pass"
modify_value TLBB_DB_PORT     "数据库端口"   "$TLBB_DB_PORT"     "3306"     "port"
modify_value TLBB_LOGIN_PORT  "登录端口"     "$TLBB_LOGIN_PORT"  "13580"    "port"
modify_value TLBB_GAME_PORT   "游戏端口"     "$TLBB_GAME_PORT"   "15680"    "port"
modify_value TLBB_WEB_PORT    "网站端口"     "$TLBB_WEB_PORT"    "51888"    "port"
modify_value TLBB_GM_PORT     "GM网站端口"   "$TLBB_GM_PORT"     "61888"    "port"
modify_value TLBB_BILLING_PORT "billing端口" "$TLBB_BILLING_PORT" "21818"   "port"

# 修改数据库实际密码
change_db_password

echo ""
echo "${CSUCCESS}配置写入成功!! 可以使用【 curgs 】命令查看配置信息${CEND}"
echo "${CYELLOW}重要: 修改端口/密码后, 请重启服务端(tl_restart), 并使用 setini 重新写入服务端配置${CEND}"
exit 0
