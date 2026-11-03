#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Load only the display function, never the host's private runtime configuration.
source <(sed -n '/^show_config() {$/,/^}$/p' "$ROOT/cmd/curgs.sh")
show_config > "$WORK/output"
grep -Fqx '  GS游享网 | 非 Docker 原生版 (gstlenv 命令体系)' "$WORK/output"
grep -Fqx '  当前项目 (非 Docker 原生版):' "$WORK/output"
grep -Fqx '    GitHub: https://github.com/yulinzhihou/gstlenv_non_docker' "$WORK/output"
grep -Fqx '    Gitee : https://gitee.com/yulinzhihou/gstlenv_non_docker' "$WORK/output"
grep -Fqx '  参考项目 (Docker 版 gstlenv):' "$WORK/output"
grep -Fqx '    GitHub: https://github.com/yulinzhihou/gstlenv' "$WORK/output"
grep -Fqx '    Gitee : https://gitee.com/yulinzhihou/gstlenv' "$WORK/output"
[ "$(sed -n '/当前项目/,/参考项目/p' "$WORK/output" | grep -c '/gstlenv_non_docker$')" = 2 ]
[ "$(sed -n '/参考项目/,/---/p' "$WORK/output" | grep -c '/gstlenv$')" = 2 ]
echo 'PASS: curgs distinguishes the native project from Docker reference links'
