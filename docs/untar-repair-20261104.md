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

下面先下载并检查所有修改过的命令，再更新本地源码和全局命令，不修改数据库、密码或运行配置：

```bash
(
    set -e
    project=/root/.tlgame
    if [ -f /root/.gs/.env ]; then
        source /root/.gs/.env
        project="${GS_PROJECT:-$project}"
    fi
    [ -d "$project/cmd" ] || { echo "未找到源码目录: $project/cmd"; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    base=https://raw.githubusercontent.com/yulinzhihou/gstlenv_non_docker/main/cmd
    for name in untar setini color gsfix change; do
        curl -fsSL "$base/$name.sh" -o "$tmp/$name.sh"
        bash -n "$tmp/$name.sh"
    done
    for name in untar setini color gsfix change; do
        install -m 755 "$tmp/$name.sh" "$project/cmd/$name.sh"
        install -m 755 "$tmp/$name.sh" "/usr/local/bin/$name"
    done
    echo "命令更新完成"
)
```

确认更新成功后，先检查原包及配置，注意不要公开包含密码的整个 `.env`：

```bash
ls -lh /root/tlbb.tar.gz /root/tlbb.zip 2>/dev/null
grep '^TLBB_PATH=' /root/.gs/.env
find /tlgame -type d -path '*/Server/Config' -print 2>/dev/null
```

原包仍在 `/root` 时直接重试；若旧脚本已重命名原包，可把实际文件路径传给 `untar`，
不必删除已有目录或重新上传：

```bash
untar && setini
# 或: untar /root/实际保留的压缩包.tar.gz && setini
```

## 验证

`tests/test_untar.sh` 使用真实 tar/zip 压缩包覆盖首次部署、替换备份、平铺/嵌套目录、
带空格路径、附属文件保留、损坏或歧义结构、备份与最终移动失败恢复、问题链接检查。

`tests/smoke_archive_commands.sh` 已在一次性 CentOS Stream 9 和 10 容器中执行真实
`untar`/`setini` 命令入口，验证默认上传路径、归一后的配置位置、缺失文件报错及原生 Issues。
这些是合成服务端目录，不执行或验证用户实际游戏二进制。
