#!/bin/bash
# ============================================================
# verify_offline.sh - 全发行版 minimal 离线安装一键验证工具
# ------------------------------------------------------------
# 用法 (在任意目标机执行):
#   bash scripts/verify_offline.sh                 # 自动检测+离线安装+验证
#   bash scripts/verify_offline.sh --kill-net      # 额外删除默认路由, 严格断网验证
#   bash scripts/verify_offline.sh --dbpass 123456 # 指定数据库密码
#
# 流程: 系统识别 -> 离线包完整性检查 -> 断网(可选) -> 离线安装
#       -> 4 项功能验证 -> 输出 PASS/FAIL 报告
# ============================================================
export LC_ALL=C
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT="$(dirname "$SCRIPT_DIR")"
KILL_NET=0
DBPASS="${TLBB_DB_PASS:-gsgameshare.com}"

log()  { echo -e "\033[32m[验证] $*\033[0m"; }
warn() { echo -e "\033[33m[警告] $*\033[0m"; }
die()  { echo -e "\033[31m[失败] $*\033[0m"; exit 1; }

for a in "$@"; do
    case "$a" in
        --kill-net) KILL_NET=1;;
        --dbpass)   shift; DBPASS="$1";;
    esac
done

# ---------- 1. 系统识别 ----------
. "$ROOT/modules/detect.sh"
detect_system
log "目标系统: ${SYS_PRETTY:-$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)}"
log "识别结果: family=${SYS_FAMILY} branch=${SYS_BRANCH} arch=${SYS_ARCH} id=${SYS_ID} ver=${SYS_VERSION_ID} cloud=${SYS_IS_CLOUD}"

# ---------- 2. 离线包完整性检查 ----------
OFFDIR="$ROOT/offline"
check_offline() {
    case "$SYS_BRANCH" in
        el5|el6|el7|el8|el9|el10)
            local d="$OFFDIR/rpm-packages/$SYS_BRANCH"
            local mysql_dir
            mysql_dir=$(ls -d "$d"/mysql* 2>/dev/null | head -1)
            [ -z "$mysql_dir" ] && return 1
            local n; n=$(ls "$mysql_dir" 2>/dev/null | wc -l)
            [ "$n" -lt 2 ] && return 1
            echo "$d (mysql ${n} 包)"
            ;;
        ubuntu)
            local u="ubuntu${SYS_VERSION_ID%%.*}"
            [ -z "$SYS_VERSION_ID" ] && u="ubuntu24"
            local d="$OFFDIR/deb-packages/$u"
            [ -d "$d" ] && { echo "$d ($(ls "$d" | wc -l) deb)"; return 0; }
            return 1
            ;;
        debian)
            warn "Debian ${SYS_VERSION_ID} 官方无 mysql-server (MariaDB 取代), 需 mysql-community 源, 无法离线验证"
            return 2
            ;;
        *) return 1;;
    esac
}
OFFMSG=$(check_offline)
case $? in
    0) log "离线包完整: $OFFMSG";;
    1) warn "未找到匹配离线包! 请先在有网机器执行: bash scripts/download_offline.sh --full ${SYS_BRANCH} [档位]"; exit 1;;
    2) exit 0;;
esac

# ---------- 3. 可选断网 (严格离线模拟) ----------
if [ "$KILL_NET" = "1" ]; then
    log "严格断网模式: 删除默认路由..."
    GW=$(ip route | awk '/^default/{print $3; exit}')
    ip route del default 2>/dev/null
    curl -sI --connect-timeout 3 --max-time 5 https://mirrors.aliyun.com >/dev/null 2>&1 && warn "仍可联网(可能走内网代理), 继续" || log "外网已断开"
fi

# ---------- 4. 离线安装 ----------
log "开始离线安装 (MySQL 档位自动匹配, 密码 ${DBPASS})..."
START=$(date +%s)
TLBB_OFFLINE_MODE=1 TLBB_DB_PASS="$DBPASS" bash "$ROOT/install.sh" --offline
RC=$?
END=$(date +%s)
log "安装命令退出码: ${RC} (耗时 $((END - START)) 秒)"

# ---------- 5. 功能验证 ----------
PASS=0; FAIL=0
v_ok()  { log "  [PASS] $1"; PASS=$((PASS + 1)); }
v_bad() { warn "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

# 5.1 数据库
if mysqladmin ping >/dev/null 2>&1 || mysql -uroot -p"$DBPASS" -e "SELECT 1" >/dev/null 2>&1; then
    v_ok "数据库运行中 (MySQL $(mysql -uroot -p"$DBPASS" -N -e 'SELECT VERSION()' 2>/dev/null))"
else
    v_bad "数据库未运行"
fi
# 5.2 库与表
T=$(mysql -uroot -p"$DBPASS" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='tlbbdb'" 2>/dev/null)
[ "${T:-0}" -gt 0 ] && v_ok "tlbbdb 导入成功 (${T} 张表)" || v_bad "tlbbdb 无表"
# 5.3 ODBC
if command -v isql >/dev/null 2>&1 && grep -q tlbbdb /etc/odbc.ini 2>/dev/null; then
    v_ok "unixODBC isql + DSN(tlbbdb) 就位"
else
    v_bad "ODBC 未就位"
fi
# 5.4 Redis
if command -v redis-cli >/dev/null 2>&1; then
    RP=$(redis-cli -a "$DBPASS" ping 2>/dev/null || redis-cli ping 2>/dev/null)
    [ "$RP" = "PONG" ] && v_ok "Redis 运行中 (密码 $DBPASS)" || v_bad "Redis 未响应"
else
    warn "  [SKIP] 系统无 redis-cli (el5/el6 官方无 redis 包)"
fi

# ---------- 6. 报告 ----------
echo ""
echo "=========================================================="
echo " 验证报告 - $(hostname) ($(date '+%Y-%m-%d %H:%M'))"
echo " 系统    : ${SYS_PRETTY}"
echo " 识别    : family=${SYS_FAMILY} branch=${SYS_BRANCH} cloud=${SYS_IS_CLOUD}"
echo " 离线包  : ${OFFMSG}"
[ "$KILL_NET" = "1" ] && echo " 断网模式: 已删除默认路由"
echo " 结果    : PASS=${PASS} FAIL=${FAIL} (安装退出码 ${RC})"
echo "=========================================================="
[ "$FAIL" = "0" ] && [ "$RC" = "0" ] && log "结论: 全部通过 ✅" || die "存在失败项, 请检查上方日志"
