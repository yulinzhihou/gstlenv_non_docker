#!/bin/bash
# ============================================================
# upow - 配置开服网站 (参考 gstlenv upow.sh, 原生版)
# 创建开服网站目录 /tlgame/www/ow, 上传网站内容即可访问
# 用法: upow
# ============================================================
[ -f /usr/local/bin/color ] && . /usr/local/bin/color
[ $(id -u) != "0" ] && { echo "${CFAILURE}错误: 你必须使用ROOT用户${CEND}"; exit 1; }
[ -f /root/.tlbb/tlbb.env ] && . /root/.tlbb/tlbb.env
TLBB_HOME="${TLBB_HOME:-/home/tlbb}"

# 网站根目录 (对齐 gstlenv /tlgame/www/ow)
WWW_ROOT="${TLBB_WWW_ROOT:-/tlgame/www}"
OW_DIR="$WWW_ROOT/ow"

# 创建目录
mkdir -p "$OW_DIR"

# 生成默认首页 (占位)
if [ ! -f "$OW_DIR/index.html" ]; then
cat >"$OW_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>TLBB 开服网站</title></head>
<body>
<h1>TLBB 开服网站</h1>
<p>请将你的开服网站内容上传到 <b>$OW_DIR</b> 目录</p>
<p>首页文件必须为: index.html / index.htm / default.html / default.htm 中的一种</p>
</body>
</html>
EOF
fi

chmod -R 777 "$OW_DIR"
echo "${CSUCCESS}创建成功! 请将网站上传到 ${OW_DIR} 目录里面, 并且首页必须是 index.html / index.htm / default.html / default.htm 中的一种${CEND}"
echo "${CYELLOW}本机部署: 将 ${OW_DIR} 挂载到你的 Web 服务(Nginx/Apache)即可访问${CEND}"
echo "${CYELLOW}如未安装 Web 服务, 可选用: yum/dnf/apt install nginx 或 apache, 并将网站根目录指向 ${OW_DIR}${CEND}"
exit 0
