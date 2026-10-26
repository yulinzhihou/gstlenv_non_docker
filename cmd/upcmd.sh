#!/bin/bash
# ============================================================
# upcmd - 重新部署全局命令 (参考 gstlenv upcmd.sh, 原生版)
# 从环境包 cmd/ 目录重新部署全部 gs 命令到 /usr/local/bin
# 用法: upcmd
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
PROJECT_DIR="${TLBB_PROJECT_DIR:-/opt/tlbb-env-pkg}"

CMD_DIR="$PROJECT_DIR/cmd"
[ -d "$CMD_DIR" ] || { echo "${CRED}未找到命令目录: $CMD_DIR (请检查环境包路径)${CEND}"; exit 1; }

# 部署全部命令: gs 原名 + tl_ 兼容名
count=0
for f in "$CMD_DIR"/*.sh; do
    [ -f "$f" ] || continue
    local name; name=$(basename "$f" .sh)
    # color 为公共库, 部署为 color
    if [ "$name" = "color" ]; then
        cp -f "$f" /usr/local/bin/color && chmod +x /usr/local/bin/color
        count=$((count + 1))
        continue
    fi
    # gs 命令原名 (对齐 gstlenv)
    cp -f "$f" "/usr/local/bin/${name}" && chmod +x "/usr/local/bin/${name}"
    # tl_ 前缀兼容名 (tl 菜单除外)
    if [ "$name" != "tl" ]; then
        cp -f "$f" "/usr/local/bin/tl_${name}" && chmod +x "/usr/local/bin/tl_${name}"
    fi
    count=$((count + 1))
done

echo "${CSUCCESS}命令重新生成成功, 共部署 ${count} 个命令到 /usr/local/bin${CEND}"
echo "${CYELLOW}如果需要了解详情, 可以运行【 gs 】命令进行帮助查询!!${CEND}"
exit 0
