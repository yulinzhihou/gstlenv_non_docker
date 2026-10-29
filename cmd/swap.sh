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

# comment: 设置虚拟内存，防止系统内存不足，导致服务端进程被杀
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }

# 默认 4G 虚拟内存 (对齐 gstlenv: 100M x 40 = 4G), 可选参数指定大小(GB)
SWAP_SIZE=${1:-4}
if [[ ! "${SWAP_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${CRED}参数错误, 请输入虚拟内存大小(G), 如: swap 4${CEND}"
    exit 1
fi
# 确保 /usr/swap 存在
mkdir -p /usr/swap

# 判断当前环境是否已经配置过虚拟内存,如果配置过，就停止，并提示
if [ -f /usr/swap/swapfile ]; then
    echo -e "${CRED}当前环境已经配置过虚拟内存,如果需要重新配置，请先删除 [/usr/swap/swapfile] 再执行本命令${CEND}"
    exit 1
fi

# 写入虚拟内存配置,并检测是否成功
if dd if=/dev/zero of=/usr/swap/swapfile bs=100M count=$((SWAP_SIZE * 10)) >/dev/null 2>&1; then
    chmod 600 /usr/swap/swapfile
    mkswap /usr/swap/swapfile >/dev/null 2>&1
    swapon /usr/swap/swapfile >/dev/null 2>&1
    echo "/usr/swap/swapfile swap swap defaults 0 0" >>/etc/fstab 2>/dev/null
    echo -e "${CSUCCESS}内存+虚拟缓存： ($(free -g | grep Mem | awk '{print $2}')G + ${SWAP_SIZE}.0G) 成功！并且成功增加到开机自动加载！！${CEND}"
    exit 0
else
    echo -e "${GSISSUE}\r\n"
    echo -e "${CRED}虚拟内存设置失败！${CEND}"
    exit 1
fi
