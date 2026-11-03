#!/usr/bin/env bash
# Author: yulinzhihou <yulinzhihou@gmail.com>
# Project: https://github.com/yulinzhihou/gstlenv_non_docker.git
# Date :  2026-11-03
# Notes:  gstlenv_non_docker - 离线组件多版本清理工具
# comment: 清理 offline/ 中每个软件的多版本 rpm/deb, 每个软件每个发行版只保留最新版本一套

# ============================================================
# prune_offline.sh - 离线组件多版本清理工具
# ------------------------------------------------------------
# 用途: 下载脚本每次运行可能残留同软件多个版本 (补丁版/跨源混装),
#       本工具按"每个软件 (同架构) 只保留最新版本"清理, 保持离线包精简。
# ------------------------------------------------------------
# 规则:
#   1) rpm-packages/<branch>/mysql<ver>/ 目录: 只保留主版本锚定的包
#      (mysql80 目录只留 8.0.x, 排除混入的 mysql 8.4 module 包等)
#   2) 其他目录 (nginx/php/redis/odbc/compat 及根目录): 按 (包名, 架构) 分组,
#      每组保留版本号最高 (sort -V 语义) 的一个文件, 其余删除
#   3) deb 目录: 按 (包名, 架构) 分组保留最新
# 用法:
#   bash scripts/prune_offline.sh            # 执行清理 (删除的文件记录到 offline/pruned-*.log)
#   bash scripts/prune_offline.sh --dry-run  # 仅预览, 不删除
# ------------------------------------------------------------
export LC_ALL=C
DRY=0
[ "$1" = "--dry-run" ] && DRY=1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PKG_ROOT="${TLBB_PKG_ROOT:-$(dirname "$SCRIPT_DIR")}"
OFFLINE="$PKG_ROOT/offline"
[ -d "$OFFLINE" ] || { echo "[错误] 不存在: $OFFLINE"; exit 1; }

PY=python3
command -v "$PY" >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || { echo "[错误] 需要 python3 或 python (用于包名/版本解析)"; exit 1; }

# Windows git bash 下 python 需要 Windows 路径
WOFFLINE="$OFFLINE"
command -v cygpath >/dev/null 2>&1 && WOFFLINE=$(cygpath -w "$OFFLINE")

echo "[清理] 扫描离线目录: $OFFLINE (dry-run=$DRY)"
$PY - "$WOFFLINE" "$DRY" <<'PYEOF'
import os, re, sys, shutil, time

root, dry = sys.argv[1], sys.argv[2] == "1"
removed, kept = set(), []
logfile = os.path.join(root, "pruned-%s.log" % time.strftime("%Y%m%d%H%M%S"))

def rm(fp):
    # 统一删除入口: 去重 + dry-run 不删 + 存在才删
    if fp in removed:
        return
    removed.add(fp)
    if not dry and os.path.exists(fp):
        os.remove(fp)

def rpm_parts(fn):
    # rpm: NAME-VER-REL.ARCH.rpm; NAME=第一个 -数字 前的部分
    m = re.match(r'^(.*?)-(\d+.*)\.rpm$', fn)
    if not m:
        return None
    name, rest = m.group(1), m.group(2)
    # 架构 = 扩展名前最后 . 段 (i686/x86_64/noarch...)
    arch = rest.rsplit(".", 1)[-1]
    ver = rest[: -(len(arch) + 1)]
    return name, ver, arch

def deb_parts(fn):
    # deb: name_version_arch.deb
    m = re.match(r'^(.+?)_(.+)_([^_]+)\.deb$', fn)
    if not m:
        return None
    return m.group(1), m.group(2), m.group(3)

def ver_key(ver):
    # 版本比较: 按 [. -] 分段, 数字段数值比较, 其余字符串比较; 段数不足补 0
    parts = re.split(r'[.\-+]', ver)
    keys = []
    for p in parts:
        if p.isdigit():
            keys.append((0, int(p), ""))
        else:
            m = re.match(r'^(\d+)(.*)$', p)
            if m:
                keys.append((1, int(m.group(1)), m.group(2)))
            else:
                keys.append((2, 0, p))
    return keys

def higher(a, b):
    ka, kb = ver_key(a[1]), ver_key(b[1])
    for x, y in zip(ka, kb):
        if x != y:
            return x > y
    return len(ka) > len(kb)

# mysql<ver> 目录锚定主版本
def mysql_anchor(d):
    m = re.search(r'/mysql(\d+)$', d.replace("\\", "/"))
    if not m:
        return None
    v = m.group(1)
    return {"80": "8.0", "84": "8.4", "57": "5.7", "51": "5.1"}.get(v)

# 组件目录语义: 目录名 -> 允许的文件名前缀 (正则); 不匹配的视为误下载的多余包, 删除
COMPONENT_PREFIX = {
    "nginx": r"^(nginx|pcp-pmda-nginx)-",          # pcp-pmda-nginx 为 nginx 监控依赖, 保留最新
    "php":   r"^(php|php8|php7|oniguruma|libzip|libargon2)-",
    "redis": r"^(redis|valkey)-",
    "odbc":  r"^(unixODBC|mysql-connector-odbc|mariadb-connector-odbc|libmyodbc|myodbc|libiodbc|odbcinst|libodb)",
}

def dir_semantic_ok(dirname, fn):
    """组件子目录中, 包名必须与目录语义匹配 (只对直接子目录生效)"""
    for key, pat in COMPONENT_PREFIX.items():
        if os.path.basename(dirname) == key:
            return re.match(pat, fn) is not None
    return True

for dirpath, dirs, files in os.walk(root):
    anchor = mysql_anchor(dirpath)
    rpms = [f for f in files if f.endswith(".rpm")]
    debs = [f for f in files if f.endswith(".deb")]
    # 0) 组件子目录: 删除与目录语义不符的多余包
    for f in list(rpms) + list(debs):
        if not dir_semantic_ok(dirpath, f):
            rm(os.path.join(dirpath, f))
            if f in rpms: rpms.remove(f)
            if f in debs: debs.remove(f)
    # 1) mysql<ver> 目录: 剔除不匹配主版本的包
    if anchor and rpms:
        for f in rpms:
            parts = rpm_parts(f)
            if parts and ("-%s." % anchor) not in f and ("-%s-" % anchor) not in f:
                rm(os.path.join(dirpath, f))
        rpms = [f for f in rpms if os.path.exists(os.path.join(dirpath, f))]
    # 2) rpm 按 (name, arch) 分组保留最新
    groups = {}
    for f in rpms:
        parts = rpm_parts(f)
        if not parts:
            continue
        groups.setdefault((parts[0], parts[2]), []).append((f, parts[1], parts[0], parts[2]))
    for key, items in groups.items():
        best = items[0]
        for it in items[1:]:
            if higher(it, best):
                best = it
        for it in items:
            if it is best or it == best:
                continue
            rm(os.path.join(dirpath, it[0]))
    # 3) deb 按 (name, arch) 分组保留最新
    dgroups = {}
    for f in debs:
        parts = deb_parts(f)
        if not parts:
            continue
        dgroups.setdefault((parts[0], parts[2]), []).append((f, parts[1], parts[0], parts[2]))
    for key, items in dgroups.items():
        best = items[0]
        for it in items[1:]:
            if higher(it, best):
                best = it
        for it in items:
            if it is best or it == best:
                continue
            rm(os.path.join(dirpath, it[0]))

print("[清理] 待删除 %d 个多版本文件%s" % (len(removed), " (dry-run 未删除)" if dry else ""))
for fp in sorted(removed):
    rel = os.path.relpath(fp, root)
    print("  删除: %s" % rel)
    if not dry:
        with open(logfile, "a", encoding="utf-8") as fh:
            fh.write(rel + "\n")
if not dry:
    print("[清理] 删除清单已记录到: %s" % os.path.join(root, os.path.basename(logfile)))
PYEOF
