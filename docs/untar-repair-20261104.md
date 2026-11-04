# untar 解压路径及错误链接修复（2026-11-04）

## 故障原因

旧命令先尝试备份 `TLBB_PATH`（默认 `/tlgame/tlbb`），然后用 `&&` 串联删除、解压、
原包重命名。首次部署时目标目录不存在，备份返回失败，后面的解压根本没有执行，
但脚本仍无条件输出“已经解压成功”并返回 0。这个情形下 `/root/tlbb.tar.gz` 通常仍在原处。

旧命令原本使用 `tar ... -C /tlgame`，没有处理包内目录层级；即便执行了解压，
包内不是标准 `tlbb/Server/` 结构，也可能落到 `/tlgame/Server/` 或其他嵌套路径。
用户机器的实际状态仍需检查，不能仅凭旧成功提示确认文件已经展开。

## 新行为

- 默认读取 `/root/tlbb.tar.gz`，其次 `/root/tlbb.zip`，也支持 `untar /绝对路径/压缩包`。
- 部署目标使用配置中的 `TLBB_PATH`，默认 `/tlgame/tlbb`，不依赖执行命令时所在目录。
- 先在目标父目录下的私有临时目录解压，识别唯一的 `Server/Config`，检查三份 INI 文件。
- 标准 `tlbb/Server/`、直接的 `Server/`、额外嵌套目录均归一到目标目录。
- 首次部署跳过旧端备份；换端时先成功备份，再替换目录，最终移动失败会尝试恢复旧端。
- 损坏包、缺失配置、多套服务端、危险成员路径或备份失败均返回非零，保留原包与旧端。
- 成功时打印源包、服务端目录、配置目录、旧端备份及原包重命名后的保存路径。
- 包内附属文件保留到目标旁的 `tlbb.archive-extra-*`，不混入其他系统目录。
- `setini` 在配置缺失时显示实际目标路径，不继续写入空配置。
- 公共错误提示和 `gsfix` 指向原生项目的 Issues，README 中 Docker 参考链接明确标记。

默认旧端备份路径由 `BACKUP_DIR` 决定（安装器默认 `/tlgame/backup`），备份权限为 `600`。
新端部署不自动修改数据库；换端前请先停服，确认新端正常后再自行清理备份。

## 仅更新命令，不重装环境

### 为什么 upcmd 提示成功，untar 还是旧版

旧 `upcmd` 只把 `${GS_PROJECT}/cmd/*.sh` 复制到 `/usr/local/bin`，完全没有联网拉取。
本地源码旧，重复执行它仍然部署旧命令。“共 35 个命令”只表示复制计数，不是远程版本号；
旧成功判断也只检查最后一次操作，不能证明整批命令成功。

手动 `tar zxf tlbb.tar.gz -C /tlgame` 能展开，说明该包可以被 tar 读取。
日志中仍出现“服务端文件【tlbb.tar.gz】已经解压成功”则是旧脚本的提示，
不是本次修复后的“源压缩包 / 目标目录 / 服务端解压并校验成功”。
另外可用 `type -a untar` 排查别名、函数及 PATH 中其他旧脚本的遮蔽。

新版 `upcmd` 默认在线获取原生项目 `main` 快照，优先 GitHub，失败再尝试 Gitee；
下载或校验均失败时返回失败，不悄悄回退到旧源码。它先检查所有命令的 Bash 语法，
准备好两份命令及旧文件恢复副本，再同步本地源码 `cmd/` 和 `/usr/local/bin`，
逐个比较内容与可执行权限。中途失败尝试恢复旧文件，只有全部校验通过才报成功，
并打印来源、源码包/命令清单/untar 的 SHA256 和安装路径。
更新有互斥锁；不运行安装器，不改 `.env`、密码、SQL、数据库或游戏目录。
SHA256 用于识别下载和部署内容，不是独立签名或发行版本认证。

`upcmd --local` 明确表示只离线重部署本地命令，不代表获取远程更新。
`gsfix` 使用这个选项，并在命令部署失败时停止，不再隐藏错误。

### 老机器的一次性升级

旧的 `upcmd` 不会下载自身，不能只再次运行它。下面先下载并检查新版更新器，
运行后由它整批更新命令；失败时不再继续执行解压。不重装环境：

```bash
(
    set -e
    tmp=$(mktemp)
    trap 'rm -f -- "$tmp"' EXIT
    curl -fsSL --connect-timeout 15 --max-time 120 \
        https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/cmd/upcmd.sh -o "$tmp"
    bash -n "$tmp"
    bash "$tmp"
)
```

确认更新成功后，先检查原包及配置，注意不要公开包含密码的整个 `.env`：

```bash
hash -r
type -a untar
grep -n '解压并校验成功' /usr/local/bin/untar
ls -lh /root/tlbb.tar.gz /root/tlbb.zip 2>/dev/null
grep '^TLBB_PATH=' /root/.gs/.env
find /tlgame -type d -path '*/Server/Config' -print 2>/dev/null
```

原包仍在 `/root` 时直接重试；若旧脚本已重命名原包，可把实际文件路径传给 `untar`，
不必删除已有目录或重新上传：

```bash
/usr/local/bin/untar && /usr/local/bin/setini
# 或: untar /root/实际保留的压缩包.tar.gz && setini
```

如果已经手动展开到 `/tlgame/tlbb/Server/Config`，不必再次覆盖解压。
先确认三份 INI 与实际配置路径，再执行 `setini`。如果服务端已在运行，换端前先停服。
此后正常在线更新使用 `upcmd` 即可；只有明确想从本机源码重新部署才使用 `upcmd --local`。

## 验证

`tests/test_untar.sh` 使用真实 tar/zip 压缩包覆盖首次部署、替换备份、平铺/嵌套目录、
带空格路径、附属文件保留、损坏或歧义结构、备份与最终移动失败恢复、问题链接检查。

`tests/smoke_archive_commands.sh` 已在一次性 CentOS Stream 9 和 10 容器中执行真实
`untar`/`setini` 命令入口，验证默认上传路径、归一后的配置位置、缺失文件报错及原生 Issues。
这些是合成服务端目录，不执行或验证用户实际游戏二进制。

`tests/test_upcmd.sh` 覆盖两处目录同步、真实路径与哈希、语法/文件/下载失败、镜像回退、
安装或校验失败回滚及权限保留。`tests/smoke_upcmd.sh` 在一次性容器中使用受控远程快照
执行真实更新器（含自更新），随后真实运行 `untar` 验证上传文件进入 `/tlgame/tlbb`，
并检查显式离线、下载失败、互斥锁、PATH 遮蔽提示及 `gsfix` 失败传播。
