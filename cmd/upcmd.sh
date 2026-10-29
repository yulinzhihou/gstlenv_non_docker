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

# comment: 更新全局命令 (从环境包 cmd/ 重新部署, 对齐 gstlenv upcmd)
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

CMD_DIR="${GS_PROJECT:-/root/.tlgame}/cmd"
[ -d "$CMD_DIR" ] || CMD_DIR="$(dirname "$0")/../cmd"
[ -d "$CMD_DIR" ] || { echo -e "${GSISSUE}\r\n"; echo -e "${CRED}未找到 cmd/ 命令目录, 请确认环境包路径!${CEND}"; exit 1; }

count=0
for f in "$CMD_DIR"/*.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .sh)
    cp -f "$f" "/usr/local/bin/${name}" && chmod +x "/usr/local/bin/${name}" && count=$((count + 1))
done
# 统一入口 gsctl
if [ -f "$CMD_DIR/gsctl.sh" ]; then
    cp -f "$CMD_DIR/gsctl.sh" /usr/local/bin/gsctl && chmod +x /usr/local/bin/gsctl
fi

if [ $? -eq 0 ]; then
    echo -e "${CSUCCESS}命令更新成功, 共 ${count} 个命令. 输入 【gs】 查看命令帮助!${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}命令更新失败!${CEND}"
    exit 1
fi