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

# comment: 设置默认充值点数,元宝，赠点，帮贡，门贡,潜能,金币 (交互与 gstlenv 完全一致)
if [ ! -f /root/.gs/.env ]; then
    echo -e "${GSISSUE}\r\n"
    echo "${CRED}环境未初始化，需要重新安装或者移除现有的环境重新安装！！！${CEND}"
    exit 1
fi

TL_MYSQL_PASSWORD="${TL_MYSQL_PASSWORD:-123456}"

# 不传参数，表示一切归零，还原默认值
if [ $# -eq 0 ]; then
    mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "ALTER TABLE \`web\`.\`account\` ALTER COLUMN point SET DEFAULT 0;" 2>/dev/null
    echo -e "${CSUCCESS}已还原【充值点】默认值为0, 如果未成功，请将角色下线再继续尝试${CEND}"
    exit 0
fi

# 分2个参数和3个参数，4个参数
# 2个参数：设置成功后，所有角色有效果。 setpoint point 123
# 3个参数：设置成单个账号的第一个角色有效果。 setpoint point 123 abcd
# 4个参数：设置成单个账号的指定角色有效果(角色序号从1开始)。 setpoint point 123 abcd 1
if [ $# -eq 2 ] || [ $# -eq 3 ] || [ $# -eq 4 ]; then
    FIRST_PARAM='point'
    SECOND_PARAM=0
    THIRD_PARAM=''
    FOURTH_PARAM=''

    case $1 in
    'point' | 'p' | 'POINT' | 'P' | '充值点') FIRST_PARAM='point' ;;
    'yuanbao' | 'y' | 'YUANBAO' | 'Y' | '元宝') FIRST_PARAM='yuanbao' ;;
    'zengdian' | 'z' | 'ZENGDIAN' | 'Z' | '赠点') FIRST_PARAM='zengdian' ;;
    'menpaipoint' | 'm' | 'MENPAIPOINT' | 'M' | '门贡') FIRST_PARAM='menpaipoint' ;;
    'guildpoint' | 'g' | 'GUILDPOINT' | 'G' | '帮贡') FIRST_PARAM='guildpoint' ;;
    'points' | 'po' | 'POINTS' | 'PO' | '潜能') FIRST_PARAM='points' ;;
    'vmoney' | 'v' | 'VMONEY' | 'V' | '金币') FIRST_PARAM='vmoney' ;;
    *)
        echo -e "${CWARNING}参数1：[point|p|POINT|P|充值点]\r\n[yuanbao|y|YUANBAO|Y|元宝]\r\n[zengdian|z|ZENGDIAN|Z|赠点]\r\n[menpaipoint|m|MENPAIPOINT|M|门贡]\r\n[guildpoint|g|GUILDPOINT|G|帮贡]\r\n[points|po|POINTS|PO|潜能]\r\n[vmoney|v|VMONEY|V|金币]\r\n中的任意一个,英文参数可以简写，不区分大小写。\r\n如：p 表示充值点，Y表示元宝${CEND}"
        exit 1
        ;;
    esac

    if [[ $2 =~ ^[0-9]+$ ]] && [ $2 -ge 0 ] && [ $2 -lt 2100000000 ]; then
        SECOND_PARAM=$2
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}错误:输入有误,充值点数格式不正确，请输入0-21亿之间的整数 ！！！${CEND}"
        exit 1
    fi

    if [ $# -eq 3 ]; then
        if [[ $3 =~ ^[A-Za-z0-9]+$ ]]; then
            THIRD_PARAM=$3'@game.sohu.com'
        else
            echo -e "${GSISSUE}\r\n"
            echo -e "${CRED}错误:输入有误,用户账号不需要加后缀 @game.sohu.com,只需要前面账号,并且暂不支持中文${CEND}"
            exit 1
        fi
    fi

    if [ $# -eq 4 ]; then
        if [[ $3 =~ ^[A-Za-z0-9]+$ ]]; then
            THIRD_PARAM=$3'@game.sohu.com'
        else
            echo -e "${GSISSUE}\r\n"
            echo -e "${CRED}错误:输入有误,用户账号不需要加后缀 @game.sohu.com,只需要前面账号,并且暂不支持中文${CEND}"
            exit 1
        fi

        case $4 in
        [1]) FOURTH_PARAM=0 ;;
        [2]) FOURTH_PARAM=1 ;;
        [3]) FOURTH_PARAM=2 ;;
        *) FOURTH_PARAM=0 ;;
        esac
    fi

    # 原生: 直接生成 SQL 并执行
    if [ ${FIRST_PARAM} == 'point' ]; then
        if [ $# -eq 2 ]; then
            # 设置充值点默认值 (所有新角色生效)
            mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "ALTER TABLE \`web\`.\`account\` ALTER COLUMN point SET DEFAULT ${SECOND_PARAM};" 2>/dev/null
        else
            # 离线充值: 指定账号
            mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "UPDATE \`web\`.\`account\` SET point = ${SECOND_PARAM} WHERE name = '${THIRD_PARAM}';" 2>/dev/null
        fi
    else
        if [ $# -eq 2 ]; then
            # 设置默认值 (所有新角色生效)
            mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "ALTER TABLE \`tlbbdb\`.\`t_char\` ALTER COLUMN ${FIRST_PARAM} SET DEFAULT ${SECOND_PARAM};" 2>/dev/null
        elif [ $# -eq 3 ]; then
            # 设置成单个账号的第一个角色有效果
            mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "UPDATE \`tlbbdb\`.\`t_char\` SET ${FIRST_PARAM} = ${SECOND_PARAM} WHERE aid IN ( SELECT aid FROM ( SELECT aid FROM t_char WHERE accname = '${THIRD_PARAM}' LIMIT 1 OFFSET 0 ) AS aids );" 2>/dev/null
        else
            # 设置成单个账号的指定角色有效果
            mysql -uroot -p"${TL_MYSQL_PASSWORD}" -e "UPDATE \`tlbbdb\`.\`t_char\` SET ${FIRST_PARAM} = ${SECOND_PARAM} WHERE aid IN ( SELECT aid FROM ( SELECT aid FROM t_char WHERE accname = '${THIRD_PARAM}' LIMIT 1 OFFSET ${FOURTH_PARAM} ) AS aids );" 2>/dev/null
        fi
    fi

    if [ $? -eq 0 ]; then
        echo -e "${CSUCCESS}刷【${FIRST_PARAM}】成功，如果未成功，请将角色下线再继续尝试${CEND}"
        exit 0
    else
        echo -e "${GSISSUE}\r\n"
        echo -e "${CRED}刷【${FIRST_PARAM}】失败, 请检查数据库状态！${CEND}"
        exit 1
    fi
else
    echo "${CRED}错误:输入有误,如果需要命令帮助，请使用 gs 查询 ！！！${CEND}"
    exit 1
fi
