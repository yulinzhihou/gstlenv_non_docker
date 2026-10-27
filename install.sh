#!/bin/bash
# ============================================================
# TLBB 原生环境万能安装器 (src/install.sh)
# ------------------------------------------------------------
# 以源码方式开发: 非 Docker, 直接在本机系统安装完整环境
# 参考 gstlenv(开源 Docker 版) 的命令体系, 提供 tl_* 全局管理命令
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
#   3) 安装数据库 (MySQL 5.1 离线 / MariaDB 国内源)
#   4) 安装 unixODBC + MySQL ODBC 驱动 (32 位 + 64 位)
#   5) 导入 tlbbdb / web 库
#   6) 部署 tl_* 全局管理命令 (参考 gstlenv)
# ============================================================

export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_ROOT="$SCRIPT_DIR"

# ---------- 加载模块 ----------
for m in modules/common.sh modules/detect.sh modules/rhel/install.sh modules/debian/install.sh; do
    if [ -f "$PKG_ROOT/$m" ]; then source "$PKG_ROOT/$m"; else echo "[错误] 缺少模块: $m"; exit 1; fi
done

# ---------- 生成运行环境文件 (类似 gstlenv /root/.gs/.env) ----------
gen_env() {
    local env_dir=/root/.tlbb
    mkdir -p "$env_dir" /home/tlbb /root/tlbb 2>/dev/null
    cat > "$env_dir/tlbb.env" <<EOF
# TLBB 原生环境配置 (由 install.sh 生成)
TLBB_HOME=/home/tlbb
TLBB_ROOT=/root/tlbb
TLBB_DB_HOST=127.0.0.1
TLBB_DB_PORT=3306
TLBB_DB_USER=root
TLBB_DB_PASS=${TLBB_DB_PASS}
TLBB_DB_NAME=tlbbdb
TLBB_WEB_DB=web
TLBB_ODBC_INI=/etc/odbc.ini
TLBB_PROJECT_DIR=${PKG_ROOT}
TLBB_ENV_VERSION=1.0
EOF
    chmod 600 "$env_dir/tlbb.env"
    log "运行环境文件已生成: $env_dir/tlbb.env"
}

# ---------- 部署全局管理命令 (参考 gstlenv set_command) ----------
install_cmd() {
    log "部署全局管理命令 (gs 原名 + tl_ 兼容名)..."
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
        # tl_ 前缀兼容名 (tl 菜单除外)
        if [ "$name" != "tl" ]; then
            cp -f "$f" "/usr/local/bin/tl_${name}" && chmod +x "/usr/local/bin/tl_${name}"
        fi
        count=$((count + 1))
    done
    log "命令安装完成: 共 ${count} 个命令 (输入 gs 查看帮助 / tl 查看菜单)"
}

# ---------- 完成横幅 ----------
finish_banner() {
    echo ""
    echo "=============================================================="
    echo "  TLBB 原生环境安装完成"
    echo "--------------------------------------------------------------"
    echo "  数据库 : root / ${TLBB_DB_PASS}   库: tlbbdb, web"
    echo "  ODBC   : /etc/odbc.ini (DSN=tlbbdb, 32位驱动 libmyodbc3)"
    echo "  64位驱动: /usr/lib64/libmyodbc.so (el7+ 可选)"
    echo "  服务端 : 上传 tlbb.tar.gz 到 /root 后执行: untar (或 tl_untar)"
    echo "  启动   : setini && runtlbb   状态: runtop (或 tl_setini/tl_runtlbb)"
    echo "  帮助   : gs (命令帮助)  /  tl (菜单)"
    echo "  端口   : 3306 / 7777 / 7778 / 9470 (请在安全组放行)"
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
    local need=""
    case "$SYS_FAMILY" in
        rhel)
            case "$SYS_BRANCH" in
                el5)  [ -f "$TLBB_OFFLINE_DIR/el5/unixODBC-2.2.11-el5.rpm" ] || need="el5 组件";;
                el6)  [ -f "$TLBB_OFFLINE_DIR/el6/unixODBC.rpm" ] || need="el6 组件";;
                el7)  [ -f "$TLBB_OFFLINE_DIR/el7/MySQL.tar.gz" ] || need="el7 组件";;
                el8|el9|el10)
                    [ -d "$TLBB_OFFLINE_DIR/rpm-packages/$SYS_BRANCH" ] || need="el${SYS_BRANCH#el} 的 rpm-packages (数据库/unixODBC)"
                    ;;
            esac
            ;;
        debian)
            [ -d "$TLBB_OFFLINE_DIR/deb-packages" ] || need="deb-packages (数据库/兼容库)"
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
