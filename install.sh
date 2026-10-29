#!/usr/bin/env bash
# ============================================================
# TLBB 原生环境万能安装器 (src/install.sh)
# ------------------------------------------------------------
# 以源码方式开发: 非 Docker, 直接在本机系统安装完整环境
# 参考 gstlenv(开源 Docker 版) 的命令体系, 部署 gs 原命令名
# ------------------------------------------------------------
# 用法:
#   bash install.sh                     # 交互模式 (自动检测在线/离线)
#   TLBB_DB_PASS=xxxx bash install.sh   # 免交互
#   bash install.sh --dbpass xxxx       # 指定数据库密码
#   bash install.sh --online            # 强制在线模式 (配置国内源, repo 安装)
#   bash install.sh --offline           # 强制离线模式 (无网络, 本地 rpm/deb 命令安装)
# ------------------------------------------------------------
# 支持系统 (自动识别, 一键安装):
#   RHEL 系: CentOS 5/6/7/8/9/10 | Rocky/Alma 8/9 | Oracle Linux
#            阿里云 Alinux 2/3/4 | Anolis 8/23
#            腾讯云 TencentOS 2/3/4
#            华为 openEuler 20~25 | EulerOS 2.x
#   Debian 系: Ubuntu 12~26 | Debian 10~18
# ------------------------------------------------------------
# 安装内容:
#   1) 配置国内安装源 (阿里云/腾讯/华为/163/搜狐/清华, EOL 自动归档)
#   2) 安装 32 位兼容库 (glibc.i686 等, TLBB 服务端为 32 位进程)
#   3) 安装数据库 (MySQL 5.1 / 5.7 / 8.0 多档位, 不用 MariaDB)
#   4) 安装 unixODBC + MySQL ODBC 驱动 (32 位 + 64 位)
#   5) 导入 tlbbdb / web 库
#   6) 部署 gs 原命令名 (untar/setini/runtlbb/... 与 gstlenv 完全一致) + gsctl 统一入口
# ============================================================

export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_ROOT="$SCRIPT_DIR"

# ---------- 加载模块 ----------
for m in modules/common.sh modules/detect.sh modules/rhel/install.sh modules/debian/install.sh modules/fedora/install.sh; do
    if [ -f "$PKG_ROOT/$m" ]; then source "$PKG_ROOT/$m"; else echo "[错误] 缺少模块: $m"; exit 1; fi
done

# ---------- 生成运行环境文件 (对齐 gstlenv /root/.gs/.env) ----------
gen_env() {
    local env_dir=/root/.gs
    mkdir -p "$env_dir" /tlgame /tlgame/backup /tlgame/www/ow /tlgame/www/gm /tlgame/conf.d /tlgame/billing /root/.tlgame 2>/dev/null
    local mver; mver=$(select_mysql_version)
    cat > "$env_dir/.env" <<EOF
# TLBB 原生环境配置 (由 install.sh 生成, 变量名/默认值对齐 gstlenv env.sample)
VERSION=v2.8.28
UPDATE=$(date +%Y-%m-%d)
SUFFIX=.tar.gz

# 备份目录
BACKUP_DIR=/tlgame/backup

# 环境配置根目录 (原生: /root/.gs, 与 gstlenv 一致)
GSDIR=.gs
ROOT_PATH=/root
CONFIG_FILE=.env
GS_WHOLE_PATH=/root/.gs/.env

# 游戏内注册=0，登录器注册=1
IS_DEFAULT_DLQ=0
IS_DLQ=0

# BILLING验证服务器IP
BILLING_DEFAULT_SERVER_IPADDR=127.0.0.1
BILLING_SERVER_IPADDR=127.0.0.1

# 环境包安装目录 (原生: src 包所在目录, 由安装器自动写入)
GS_PROJECT=${PKG_ROOT}
TLBB_PROJECT_DIR=${PKG_ROOT}

# 离线包上传路径以及名称 (原生预留)
OFFLINE_TAR=/root/gstlenv_offline.tar.gz

# 宿主机器与容器共享的文件夹 (原生: /tlgame 数据根目录)
SHARED_DIR=/tlgame

# BILLING 验证端口配置
BILLING_DEFAULT_PORT=21818
BILLING_PORT=21818

# MYSQL 监听端口 (原生: 本机直连, 默认 3306)
TL_MYSQL_DEFAULT_PORT=3306
TL_MYSQL_PORT=3306

# 默认服务端登录网关端口
LOGIN_DEFAULT_PORT=13580
LOGIN_PORT=13580

# 默认服务端游戏网关端口
SERVER_DEFAULT_PORT=15680
SERVER_PORT=15680

# WEB 访问端口
WEB_DEFAULT_PORT=51888
WEB_PORT=51888
WEB_DEFAULT_HTTPS_PORT=51443
WEB_HTTPS_PORT=51443

# WEB GM访问端口
WEB_GM_DEFAULT_PORT=61888
WEB_GM_PORT=61888

# MYSQL 用户
TL_MYSQL_USER=gs

# MYSQL root密码
TL_MYSQL_DEFAULT_PASSWORD=123456
TL_MYSQL_PASSWORD=${TLBB_DB_PASS}

# TL服务端在宿主主机路径 (原生: /tlgame/tlbb, 与 gstlenv 一致)
TLBB_PATH=/tlgame/tlbb
TLBB_HOME=/tlgame

# 容器时区
TZ=Asia/Shanghai

# Redis 配置
REDIS_HOST_PORT=6379

# 默认环境编号
DEFAULT_ENV_INDEX=1

# GM工具对应的配置
LOGIN_DEFAULT_USER_NAME=gsgameshare
LOGIN_USER_NAME=gsgameshare
LOGIN_DEFAULT_PASSWORD=gsgameshare.com
LOGIN_PASSWORD=gsgameshare.com
PRIVATE_DEFAULT_KEY=Gsgameshare.com2025
PRIVATE_KEY=Gsgameshare.com2025
REDIS_PASSWORD=gsgameshare.com
REDIS_DEFAULT_PASSWORD=gsgameshare.com

# 原生新增: MySQL 档位 (对齐 gstlenv 环境编号: 1=CS6+5.1 2=CS7+5.1 3=CS7+5.7 4=CS9+8.0)
TLBB_MYSQL_VERSION=${mver}
TLBB_MYSQL_USER=${TLBB_MYSQL_USER}
EOF
    chmod 600 "$env_dir/.env"
    log "运行环境文件已生成: $env_dir/.env (对齐 gstlenv env.sample)"
}

# ---------- MySQL 档位选择交互 (对齐 gstlenv 环境编号菜单) ----------
ask_mysql_version() {
    [ "$TLBB_NONINTERACTIVE" = "1" ] && return 0
    [ -n "$TLBB_MYSQL_VERSION" ] && [ "$TLBB_MYSQL_VERSION" != "auto" ] && return 0
    echo ""
    echo "  ※※※ 数据库版本选择 (对齐 gstlenv 环境编号) ※※※"
    echo "  编号1: MySQL 5.1  (老端标准, CentOS 6/7 + MySQL5.1, 默认)"
    echo "  编号2: MySQL 5.7  (改引擎端, CentOS 7/8 + MySQL5.7, 需自己替换SQL)"
    echo "  编号3: MySQL 8.0  (64位源端, CentOS 9/10/Ubuntu20+ + MySQL8.0, 需替换SQL和ini)"
    echo "  直接回车: 按系统自动选择 (auto)"
    read -e -p "请输入编号 [1|2|3, 回车=auto]: " __mysql_idx
    case "$__mysql_idx" in
        1) TLBB_MYSQL_VERSION=51;;
        2) TLBB_MYSQL_VERSION=57;;
        3) TLBB_MYSQL_VERSION=80;;
        *) TLBB_MYSQL_VERSION=auto;;
    esac
    log "数据库版本: MySQL ${TLBB_MYSQL_VERSION}"
}

# ---------- 部署全局管理命令 (参考 gstlenv set_command, 只部署 gs 原命令名) ----------
install_cmd() {
    log "部署全局管理命令 (gs 原命令名, 与 gstlenv 完全一致)..."
    local cmd_dir="$PKG_ROOT/cmd"
    [ -d "$cmd_dir" ] || { warn "未找到 cmd/ 目录, 跳过命令安装"; return 0; }
    local count=0
    for f in "$cmd_dir"/*.sh; do
        [ -f "$f" ] || continue
        local name; name=$(basename "$f" .sh)
        # color 公共库 -> /usr/local/bin/color
        if [ "$name" = "color" ]; then
            cp -f "$f" /usr/local/bin/color && chmod +x /usr/local/bin/color
            count=$((count + 1))
            continue
        fi
        # gs 原名 (对齐 gstlenv 命令体系: untar/setini/runtlbb/...)
        cp -f "$f" "/usr/local/bin/${name}" && chmod +x "/usr/local/bin/${name}"
        count=$((count + 1))
    done
    # gsctl 统一入口 (gsctl <命令> [参数], 替代原 tl_* 前缀)
    if [ -f "$cmd_dir/gsctl.sh" ]; then
        cp -f "$cmd_dir/gsctl.sh" /usr/local/bin/gsctl && chmod +x /usr/local/bin/gsctl
        count=$((count + 1))
    fi
    log "命令安装完成: 共 ${count} 个命令 (输入 gs 查看帮助 / gsctl <命令> 统一入口)"
}

# ---------- 完成横幅 ----------
finish_banner() {
    local mver; mver=$(select_mysql_version)
    echo ""
    echo "=============================================================="
    echo "  TLBB 原生环境安装完成"
    echo "--------------------------------------------------------------"
    echo "  数据库 : MySQL ${mver}  root / ${TLBB_DB_PASS}  游戏账号: ${TLBB_MYSQL_USER} / ${TLBB_MYSQL_PASSWORD}"
    echo "  库     : tlbbdb, web"
    echo "  ODBC   : /etc/odbc.ini (DSN=tlbbdb, 32位驱动 libmyodbc3)"
    echo "  64位驱动: /usr/lib64/libmyodbc.so (el7+ 可选)"
    echo "  服务端 : 上传 tlbb.tar.gz 到 /root 后执行: untar"
    echo "  启动   : setini && runtlbb   状态: runtop"
    echo "  帮助   : gs (命令帮助)  /  gsctl <命令> (统一入口)"
    echo "  端口   : 数据库 ${TLBB_MYSQL_PORT} | 登录 ${TLBB_LOGIN_PORT} | 游戏 ${TLBB_SERVER_PORT} | billing ${TLBB_BILLING_PORT} | web ${TLBB_WEB_PORT}/${TLBB_WEB_GM_PORT}"
    echo "          (默认对齐 gstlenv, 请按需在安全组放行)"
    echo "=============================================================="
    echo "  GS游享网 · 天龙八部万能环境 | 售后/帮助: gs (命令菜单)"
    echo "  出品: GS游享网 (gsgameshare.com)  仅供学习研究, 24小时内删除"
    echo "=============================================================="
}

# ---------- 网络检测与离线模式判定 ----------
detect_net() {
    # 显式指定模式优先
    [ -n "${TLBB_OFFLINE_MODE}" ] && return 0
    TLBB_OFFLINE_MODE=0
    # 尝试访问国内镜像 (3 秒超时), 失败则自动进入离线模式
    if command -v curl >/dev/null 2>&1; then
        curl -sI --connect-timeout 3 --max-time 5 https://mirrors.aliyun.com >/dev/null 2>&1 || TLBB_OFFLINE_MODE=1
    elif command -v wget >/dev/null 2>&1; then
        wget -T 5 -O /dev/null -q https://mirrors.aliyun.com >/dev/null 2>&1 || TLBB_OFFLINE_MODE=1
    else
        TLBB_OFFLINE_MODE=1   # 无网络工具, 视为离线
    fi
}

# ---------- 离线完整性检查 ----------
check_offline_complete() {
    [ "${TLBB_OFFLINE_MODE:-0}" != "1" ] && return 0
    log "离线模式: 检查本地组件完整性..."
    local mver; mver=$(select_mysql_version)
    local need=""
    case "$SYS_FAMILY" in
        rhel)
            case "$SYS_BRANCH" in
                el5)  [ -f "$TLBB_OFFLINE_DIR/el5/unixODBC-2.2.11-el5.rpm" ] || need="el5 组件";;
                el6)  [ -f "$TLBB_OFFLINE_DIR/el6/unixODBC.rpm" ] || need="el6 组件";;
                el7)
                    [ -f "$TLBB_OFFLINE_DIR/el7/MySQL.tar.gz" ] || need="el7 MySQL 5.1 离线包"
                    ;;
                el8|el9|el10)
                    [ -d "$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH/mysql${mver}" ] && \
                        find "$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH/mysql${mver}" -name '*.rpm' 2>/dev/null | grep -q . || \
                        need="el${SYS_BRANCH#el} 的 MySQL ${mver} 离线 rpm (offline/rpm-packages/$SYS_BRANCH/mysql${mver}/)"
                    ;;
            esac
            ;;
        debian)
            [ -d "$TLBB_OFFLINE_DIR/deb-packages/mysql${mver}" ] && \
                find "$TLBB_OFFLINE_DIR/deb-packages/mysql${mver}" -name '*.deb' 2>/dev/null | grep -q . || \
                need="deb-packages/mysql${mver}/ (MySQL ${mver} 离线 deb)"
            ;;
        fedora)
            fed_check_offline
            ;;
    esac
    if [ -n "$need" ]; then
        warn "离线模式缺少: $need"
        warn "请使用 src/scripts/pack_offline.sh 在联网机器上补齐, 或改用 --online"
    fi
}

# ---------- 主流程 ----------
main() {
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --dbpass) TLBB_DB_PASS="$2"; shift 2;;
            --offline-dir) TLBB_OFFLINE_DIR="$2"; shift 2;;
            --online)  TLBB_OFFLINE_MODE=0; shift;;
            --offline) TLBB_OFFLINE_MODE=1; shift;;
            -h|--help)
                grep -E '^#   ' "$0" | sed 's/^#   //'; exit 0;;
            *) shift;;
        esac
    done

    check_root
    check_arch
    brand_banner
    detect_system
    detect_cloud
    print_sysinfo

    # MySQL 档位选择 (对齐 gstlenv 环境编号菜单, 可 TLBB_MYSQL_VERSION 预置)
    ask_mysql_version

    if [ -z "$TLBB_OFFLINE_DIR" ]; then
        TLBB_OFFLINE_DIR="$PKG_ROOT/offline"
        [ -d "$TLBB_OFFLINE_DIR" ] && log "离线组件目录: $TLBB_OFFLINE_DIR" || warn "未找到 offline/ 目录"
    fi

    detect_net
    if [ "${TLBB_OFFLINE_MODE:-0}" = "1" ]; then
        log "运行模式: [离线] 无网络, 使用本地 rpm/deb 命令安装组件"
        check_offline_complete
    else
        log "运行模式: [在线] 配置国内源, 使用 repo 安装组件"
    fi

    case "$SYS_FAMILY" in
        rhel)
            log "识别为 RHEL 系 (${SYS_BRANCH} / ${SYS_PRETTY}), 开始安装..."
            rhel_install
            ;;
        debian)
            log "识别为 Debian 系 (${SYS_ID} / ${SYS_CODENAME}), 开始安装..."
            deb_install
            ;;
        fedora)
            log "识别为 Fedora (${SYS_VERSION_ID} / ${SYS_PRETTY}), 开始安装..."
            fed_install
            ;;
        *)
            err "未识别系统类型, 无法自动安装."
            err "建议: 使用 Docker 方案 (gstlenv 离线镜像) 或手动按 docs/ 文档操作"
            exit 1
            ;;
    esac

    gen_env
    install_cmd
    finish_banner
}

main "$@"
