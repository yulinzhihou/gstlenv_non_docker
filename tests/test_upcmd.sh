#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
source "$ROOT/cmd/upcmd.sh"

fixture() {
    local name
    case_dir="$WORK/$1"
    mkdir -p "$case_dir/source" "$case_dir/project/cmd" "$case_dir/bin"
    cp "$ROOT"/cmd/*.sh "$case_dir/source/"
    cp -a "$ROOT/assets" "$case_dir/assets"
    for name in "$case_dir/source"/*.sh; do
        name="${name##*/}"
        printf '#!/usr/bin/env bash\n# stale local fixture\n' > "$case_dir/project/cmd/$name"
        cp "$case_dir/project/cmd/$name" "$case_dir/bin/${name%.sh}"
    done
    chmod 700 "$case_dir/bin/untar"
}
snapshot() {
    cp -a "$case_dir/project/cmd" "$case_dir/before-cmd"
    cp -a "$case_dir/bin" "$case_dir/before-bin"
    if [ -d "$case_dir/project/assets" ]; then
        cp -a "$case_dir/project/assets" "$case_dir/before-assets"
    fi
}
unchanged() {
    diff -r "$case_dir/before-cmd" "$case_dir/project/cmd"
    diff -r "$case_dir/before-bin" "$case_dir/bin"
    if [ -d "$case_dir/before-assets" ]; then
        diff -r "$case_dir/before-assets" "$case_dir/project/assets"
    elif [ -d "$case_dir/project/assets" ]; then
        [ -z "$(find "$case_dir/project/assets" -type f -print -quit)" ]
    fi
    [ "$(stat -c %a "$case_dir/bin/untar")" = 700 ]
    ! grep -q '已校验 .* 个命令' "$case_dir/failure.log"
}
deploy() {
    upcmd_deploy "$case_dir/source" "$case_dir/project/cmd" "$case_dir/bin"
}

fixture 'paths with spaces'
printf keep > "$case_dir/project/.env"
printf keep > "$case_dir/bin/unrelated"
deploy > "$case_dir/success.log"
for file in "$case_dir/source"/*.sh; do
    name="${file##*/}"
    cmp "$file" "$case_dir/project/cmd/$name"
    cmp "$file" "$case_dir/bin/${name%.sh}"
    [ -x "$case_dir/bin/${name%.sh}" ]
done
[ "$(<"$case_dir/project/.env")" = keep ]
[ "$(<"$case_dir/bin/unrelated")" = keep ]
diff -r "$ROOT/assets" "$case_dir/project/assets"
grep -Fq "安装目录: $case_dir/bin" "$case_dir/success.log"
grep -q '命令清单 SHA256: [a-f0-9]\{64\}' "$case_dir/success.log"
grep -q 'untar SHA256: [a-f0-9]\{64\}' "$case_dir/success.log"
(cd "$case_dir/source" && sha256sum -- *.sh) > "$case_dir/expected-manifest"
manifest_digest=$(sha256sum "$case_dir/expected-manifest")
grep -Fq "命令清单 SHA256: ${manifest_digest%% *}" "$case_dir/success.log"
bash "$case_dir/bin/upcmd" --help | grep -q -- '--local'
[ -z "$(find "$case_dir" -name '.upcmd.*' -print -quit)" ]
echo 'PASS: all commands replace stale source and installed files, with verified hashes, executable modes and real paths'

fixture syntax
printf 'if then\n' >> "$case_dir/source/untar.sh"
snapshot
if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
unchanged
fixture missing
rm "$case_dir/source/untar.sh"
snapshot
if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
unchanged
fixture link
rm "$case_dir/source/untar.sh"
ln -s "$ROOT/cmd/untar.sh" "$case_dir/source/untar.sh"
snapshot
if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
unchanged
echo 'PASS: missing, symlinked or syntactically invalid command sources never alter either destination'

fixture missing-assets
rm "$case_dir/assets/billing/billing64"
snapshot
if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
unchanged
fixture corrupt-assets
printf broken >> "$case_dir/assets/billing/billing64"
snapshot
if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
unchanged
(
    fixture asset-install-failure
    cp -a "$ROOT/assets" "$case_dir/project/assets"
    printf old >> "$case_dir/project/assets/billing/billing64"
    snapshot
    mv() {
        [[ "${*: -1}" != "$case_dir/project/assets/billing/README.md" || "${*: -2:1}" != */new/assets/README.md ]] || return 1
        command mv "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    unchanged
)
echo 'PASS: missing/corrupt Billing assets abort updates; asset installation failure rolls back assets and all commands together'

for kind in symlink directory; do
    fixture "target-$kind"
    rm "$case_dir/bin/gs"
    if [ "$kind" = symlink ]; then
        ln -s "$case_dir/bin/untar" "$case_dir/bin/gs"
    else
        mkdir "$case_dir/bin/gs"
    fi
    snapshot
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    unchanged
done
echo 'PASS: destination symlinks/directories are rejected before any commands change'

(
    fixture prepare-failure
    snapshot
    install() {
        [[ "${*: -1}" != */new/untar ]] || return 1
        command install "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    unchanged
)
(
    fixture backup-failure
    snapshot
    cp() {
        [[ "${*: -1}" != */old/untar.sh ]] || return 1
        command cp "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    unchanged
)
echo 'PASS: staging or backup errors are propagated without partial deployment'

(
    fixture rename-failure
    rm "$case_dir/bin/color" "$case_dir/project/cmd/color.sh"
    snapshot
    mv() {
        [[ "${*: -1}" != "$case_dir/bin/setini" || "${*: -2:1}" != */new/setini ]] || return 1
        command mv "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    unchanged
)
(
    fixture verify-failure
    snapshot
    sha256sum() {
        [[ "${*: -1}" != "$case_dir/bin/untar" ]] || return 1
        command sha256sum "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    unchanged
)
echo 'PASS: mid-update rename and final verification errors restore old content/modes and remove newly introduced commands'

(
    fixture interruption
    snapshot
    mv() {
        if [[ "${*: -1}" = "$case_dir/bin/setini" && "${*: -2:1}" = */new/setini ]]; then
            kill -TERM "$BASHPID"
        fi
        command mv "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; else rc=$?; fi
    [ "$rc" = 143 ]
    unchanged
)
(
    fixture rollback-failure
    mv() {
        [[ "${*: -2:1}" != */old/color.sh ]] || return 1
        [[ "${*: -1}" != "$case_dir/bin/setini" || "${*: -2:1}" != */new/setini ]] || return 1
        command mv "$@"
    }
    if deploy > "$case_dir/failure.log" 2>&1; then exit 1; fi
    grep -q '回滚未完成, 请保留恢复文件' "$case_dir/failure.log"
    recovery=$(find "$case_dir/bin" -path '*/old/color.sh' -type f)
    [ -f "$recovery" ]
    grep -q 'stale local fixture' "$recovery"
)
echo 'PASS: termination rolls back commands; unsuccessful rollback preserves and reports recovery files'

mkdir -p "$WORK/remote/repository/cmd"
cp "$ROOT"/cmd/*.sh "$WORK/remote/repository/cmd/"
cp -a "$ROOT/assets" "$WORK/remote/repository/assets"
tar -czf "$WORK/remote.tar.gz" -C "$WORK/remote" repository
(
    curl() { return 22; }
    wget() {
        local output=""
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -O ]; then output="$2"; break; fi
            shift
        done
        [ -n "$output" ] && cp "$WORK/remote.tar.gz" "$output"
    }
    upcmd_download https://fixture.invalid/archive "$WORK/wget-fallback.tar.gz"
    cmp "$WORK/wget-fallback.tar.gz" "$WORK/remote.tar.gz"
)
(
    upcmd_download() { cp "$WORK/remote.tar.gz" "$2"; }
    mkdir "$WORK/fetch"
    upcmd_fetch "$WORK/fetch" > "$WORK/fetch.log"
    cmp "$UPCMD_COMMAND_DIR/untar.sh" "$ROOT/cmd/untar.sh"
    [[ "$UPCMD_SOURCE" == https://codeload.github.com/* ]]
    grep -q '源码包 SHA256:' "$WORK/fetch.log"
)
(
    upcmd_download() {
        case "$1" in
            *codeload.github.com*) printf '<html>not an archive</html>' > "$2";;
            *) cp "$WORK/remote.tar.gz" "$2";;
        esac
    }
    mkdir "$WORK/fallback"
    upcmd_fetch "$WORK/fallback" > "$WORK/fallback.log" 2>&1
    [[ "$UPCMD_SOURCE" == https://gitee.com/* ]]
    cmp "$UPCMD_COMMAND_DIR/untar.sh" "$ROOT/cmd/untar.sh"
)
(
    upcmd_download() { return 22; }
    mkdir "$WORK/no-network"
    if upcmd_fetch "$WORK/no-network" > "$WORK/no-network.log" 2>&1; then exit 1; fi
    grep -q '未使用本机旧源码冒充更新' "$WORK/no-network.log"
)
tar -czf "$WORK/traversal.tar.gz" --transform='s|^|../|' -C "$WORK/remote" repository
if upcmd_unpack "$WORK/traversal.tar.gz" "$WORK/unsafe" > "$WORK/unsafe.log" 2>&1; then exit 1; fi
grep -q '源码包路径不安全' "$WORK/unsafe.log"
echo 'PASS: remote snapshots, wget fallback and mirror fallback are validated; total failure never redeploys stale files'
if [ "${TLBB_TEST_LIVE_DOWNLOAD:-0}" = 1 ]; then
    mkdir "$WORK/live"
    upcmd_fetch "$WORK/live"
    upcmd_validate "$UPCMD_COMMAND_DIR"
    echo 'PASS: official live archive download and command syntax validation (no installation)'
fi
echo 'All command update checks passed.'
