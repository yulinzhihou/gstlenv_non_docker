# 启动路径与 step 命令（2026-11-04）

## 统一运行目录

- 游戏根目录：`/tlgame/tlbb`，启动脚本：`/tlgame/tlbb/run.sh`。
- 游戏程序：通常在 `/tlgame/tlbb/Server/`。
- Billing：`/tlgame/billing/billing`，配置：`/tlgame/billing/config.yaml`。
- 备份：`/tlgame/backup`（`BACKUP_DIR` 可配置）。

`untar` 和 `setini` 将 `run.sh` 中完整的 `/home/tlbb`、
`/home/tlbb/tlbb1` 等旧根路径替换为游戏根目录，将 `/home/billing` 替换为
`/tlgame/billing`，包含 `cd`、库路径和 `LD_PRELOAD` 中的引用。
不匹配的路径不会凭猜测修改。实际游戏路径可在 `/tlgame` 下自定义，
但不能覆盖 Billing、备份或网站目录。

旧 `.env` 若仍配置了其他运行根目录，会明确报错；请先自行备份及迁移旧数据，
修复 `/root/.gs/.env` 为 `TLBB_HOME=/tlgame`、`TLBB_PATH=/tlgame/tlbb`。
命令不会擅自改写此配置或移动游戏数据。

修改前的原脚本保存在 `${BACKUP_DIR}/run.sh-before-prepare-*`，权限 `600`。
脚本内容未变时不重复备份。路径规范化保留原有条件分支与启动命令，
不删除 `shm clear` 等原脚本逻辑。

## 升级并检查

```bash
upcmd
hash -r
setini
step --list
step --check
```

已有服务端不用再次 `untar`。只有上传新端或首次部署才需要解压。
`untar` 若提示“已解压，但 run.sh 检查未通过”，文件已在输出的目标目录，
原包也可能已改名保留；修复后直接执行 `setini`，不要再次替换游戏或重置数据库。

检查包括 Bash 语法、`cd` 目录、实际可执行程序、`shm` 对应的 `ShareMemory`、
`LD_PRELOAD` 文件与可解析环境。缺失项显示行号及完整路径，要求修复 `run.sh`。
`setini` 检查失败不继续写 INI/ODBC/Billing 配置。检查和准备不会启动游戏或 Billing。
文件存在不代表架构、动态库及游戏协议兼容，仍需通过实际运行日志验证。

本机验证模式缺少 Billing 启动项时，在脚本开头补充独立子 shell 启动项，
避免尾部 `exit` 导致它不可达，也不改变后续工作目录。
已有多处分支内的 Billing 命令保留，步骤清单按程序路径去重，不继续追加。
W机验证模式 (`IS_DLQ=1`) 不自动添加本机 Billing，发现已有启动项会提示移除。

## 分步启动

`step --list` 显示每一步的角色、实际文件、工作目录、命令及相关库环境。
排序固定为 Billing、ShareMemory/shm、Login、World、Server、其他程序。
同角色的多个实际启动项各有一步；角色缺失则不会凭空补充，编号以清单为准。

典型五程序：

```bash
step 1  # /tlgame/billing/billing up -d
step 2  # /tlgame/tlbb/Server/shm start
step 3  # /tlgame/tlbb/Server/Login
step 4  # /tlgame/tlbb/Server/World
step 5  # 实际 Server / Server1 / Server_fix 命令
```

`step billing` 是本机 Billing 的快捷选择；无参数 `step` 列表后交互选择。
不会把 `Server_fix` 强行重命名为 `Server`，也不覆盖上传的可执行文件。
保留原始参数及 `setarch x86_64 -R env LD_PRELOAD=...` 等包装命令。
符号链接按实际目标校验及匹配运行进程。

每次只执行选中的启动命令，移除输出重定向和后台符号以便前台查看错误，
继承明确导出的环境及 `ulimit -n/-c`；不执行整个 `run.sh`，也不执行其中的
`rm`、`shm clear`、`sleep`、内核参数写入。
程序前台常驻时需另开 SSH 会话继续下一步；Ctrl+C 通常会结束当前前台程序。
Billing 自身的 `up -d` 仍按原接口运行，可能自行后台化。
同路径进程已运行时拒绝重复启动，不自动停止或重启。

`runtlbb` 仍是通过检查后后台运行完整 `run.sh`，保留其原有顺序和控制流；
不会把一键启动顺序强制改成 step 排序。可用 `runtop`、`gslog` 确认实际状态。

## 静态解析范围

解析不 `source`、`eval` 或执行上传脚本。支持直接启动命令、简单变量赋值、
引号路径、CRLF/续行、`cd`、`export`/`unset`、子 shell 和常见启动包装。
条件分支只读取静态条目，不预测分支是否执行；`step` 是人工选择单条启动命令的调试工具，
不是完整 Bash 解释器。

命令替换、动态变量路径、shell `-c`、嵌套启动脚本、函数、循环和 here-document
等无法可靠解析的结构会报错或警告。请把启动程序改成明确路径及参数，
不要为通过检查而运行不明脚本。复杂控制流、管道与 shell 展开不能依赖 step 重现。
`runtop` 使用同一解析器，仅监控识别到的启动项；修改 `run.sh` 后需要重新进入监控。
