#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
source "$ROOT/cmd/untar.sh"

make_game() {
    mkdir -p "$1/Server/Config"
    for file in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
        printf '[System]\nDBIP=old\nDBPort=0\nDBName=old\nDBUser=old\nDBPassword=old\n' > "$1/Server/Config/$file"
    done
    printf '#!/bin/sh\nexit 0\n' > "$1/run.sh"
    chmod +x "$1/run.sh"
}
expect_failure() {
    local archive="$1" target="$2" backup_dir="$3" before
    before=$(cksum "$archive")
    if untar_deploy "$archive" "$target" "$backup_dir" > "$WORK/failure.log" 2>&1; then
        echo 'FAIL: deployment unexpectedly succeeded'; exit 1
    fi
    [ "$(cksum "$archive")" = "$before" ]
    ! grep -q '解压并校验成功' "$WORK/failure.log"
    [ "$(<"$target/old-data")" = preserved ]
    grep -q 'gstlenv_non_docker/issues' "$WORK/failure.log"
}

make_game "$WORK/standard/tlbb"
tar -czf "$WORK/tlbb.tar.gz" -C "$WORK/standard" tlbb
untar_deploy "$WORK/tlbb.tar.gz" "$WORK/first/tlbb" "$WORK/backups" > "$WORK/first.log"
[ -f "$WORK/first/tlbb/Server/Config/LoginInfo.ini" ]
[ -x "$WORK/first/tlbb/run.sh" ]
[ ! -e "$WORK/backups" ]
[ ! -e "$WORK/tlbb.tar.gz" ]
grep -Fqx "服务端目录: $WORK/first/tlbb" "$WORK/first.log"
[ "$(find "$WORK" -maxdepth 1 -name '*-tlbb.tar.gz' | wc -l)" = 1 ]
echo 'PASS: first deployment needs no old directory, preserves executable mode and reports the real path'

for layout in flat nested; do
    path="$WORK/$layout input"
    case "$layout" in
        flat) game="$path";;
        nested) game="$path/wrapper/tlbb2/tlbb";;
    esac
    make_game "$game"
    tar -czf "$WORK/$layout archive.tar.gz" -C "$path" .
    untar_deploy "$WORK/$layout archive.tar.gz" "$WORK/$layout output/game" "$WORK/backups" > "$WORK/$layout.log"
    [ -f "$WORK/$layout output/game/Server/Config/ShareMemInfo.ini" ]
    [ ! -d "$WORK/$layout output/game/tlbb" ]
done
echo 'PASS: flat, nested and renamed game roots normalize to TLBB_PATH, including paths with spaces'

mkdir -p "$WORK/replace/tlbb"
printf preserved > "$WORK/replace/tlbb/old-data"
tar -czf "$WORK/replace.tar.gz" -C "$WORK/standard" tlbb
untar_deploy "$WORK/replace.tar.gz" "$WORK/replace/tlbb" "$WORK/backups" > "$WORK/replace.log"
[ ! -f "$WORK/replace/tlbb/old-data" ]
backup=$(find "$WORK/backups" -name '*.tar.gz' -type f)
[ "$(tar -xOzf "$backup" tlbb/old-data)" = preserved ]
[ "$(stat -c %a "$backup")" = 600 ]
echo 'PASS: replacing an existing game produces a readable backup before deployment'

mkdir -p "$WORK/extras/input/billing"
cp -a "$WORK/standard/tlbb" "$WORK/extras/input/"
printf billing-data > "$WORK/extras/input/billing/component"
tar -czf "$WORK/extras.tar.gz" -C "$WORK/extras/input" .
untar_deploy "$WORK/extras.tar.gz" "$WORK/extras/output/tlbb" "$WORK/backups" > "$WORK/extras.log"
extra=$(find "$WORK/extras/output" -name component -type f)
[ "$(<"$extra")" = billing-data ]
grep -Fq '包内其他文件已保留:' "$WORK/extras.log"
echo 'PASS: sibling billing/assets remain available instead of being discarded'

mkdir -p "$WORK/existing/game"
printf preserved > "$WORK/existing/game/old-data"
printf broken > "$WORK/broken.tar.gz"
expect_failure "$WORK/broken.tar.gz" "$WORK/existing/game" "$WORK/backups"
mkdir -p "$WORK/invalid"
printf unrelated > "$WORK/invalid/readme"
tar -czf "$WORK/invalid.tar.gz" -C "$WORK/invalid" .
expect_failure "$WORK/invalid.tar.gz" "$WORK/existing/game" "$WORK/backups"
make_game "$WORK/ambiguous/one"
make_game "$WORK/ambiguous/two"
tar -czf "$WORK/ambiguous.tar.gz" -C "$WORK/ambiguous" .
expect_failure "$WORK/ambiguous.tar.gz" "$WORK/existing/game" "$WORK/backups"
cp -a "$WORK/standard" "$WORK/incomplete"
rm "$WORK/incomplete/tlbb/Server/Config/LoginInfo.ini"
tar -czf "$WORK/incomplete.tar.gz" -C "$WORK/incomplete" .
expect_failure "$WORK/incomplete.tar.gz" "$WORK/existing/game" "$WORK/backups"
echo 'PASS: corrupt, missing, ambiguous and incomplete game layouts fail without altering the archive or old game'

tar -czf "$WORK/traversal.tar.gz" --transform='s|^|../|' -C "$WORK/standard" tlbb
expect_failure "$WORK/traversal.tar.gz" "$WORK/existing/game" "$WORK/backups"
tar -czf "$WORK/absolute.tar.gz" --transform='s|^|/escape/|' -C "$WORK/standard" tlbb
expect_failure "$WORK/absolute.tar.gz" "$WORK/existing/game" "$WORK/backups"
printf blocked > "$WORK/backup-is-file"
tar -czf "$WORK/backup-fail.tar.gz" -C "$WORK/standard" .
expect_failure "$WORK/backup-fail.tar.gz" "$WORK/existing/game" "$WORK/backup-is-file"
echo 'PASS: unsafe archive paths and backup failure leave the existing deployment intact'

(
    tar() {
        if [ "${1:-}" = -xzf ]; then return 1; fi
        command tar "$@"
    }
    tar -czf "$WORK/extract-fail.tar.gz" -C "$WORK/standard" tlbb
    expect_failure "$WORK/extract-fail.tar.gz" "$WORK/existing/game" "$WORK/backups"
)
(
    tar() {
        if [ "${1:-}" = -czf ] && [[ "${2:-}" == *tlbb-before-untar-* ]]; then
            printf partial > "$2"
            return 1
        fi
        command tar "$@"
    }
    tar -czf "$WORK/tar-backup-fail.tar.gz" -C "$WORK/standard" tlbb
    expect_failure "$WORK/tar-backup-fail.tar.gz" "$WORK/existing/game" "$WORK/backups"
    [ -z "$(find "$WORK/backups" -name '*.partial' -print -quit)" ]
)
echo 'PASS: extraction and backup-command errors propagate without falsely reporting success'

(
    mv() {
        if [ "${1:-}" = -T ] && [ "${4:-}" = "$WORK/existing/game" ] && [[ "${3:-}" != */previous ]]; then return 1; fi
        command mv "$@"
    }
    tar -czf "$WORK/move-fail.tar.gz" -C "$WORK/standard" tlbb
    expect_failure "$WORK/move-fail.tar.gz" "$WORK/existing/game" "$WORK/backups"
)
[ -z "$(find "$WORK" -type d -name '.untar.*' -print -quit)" ]
echo 'PASS: final move failure restores the old game and cleans staging'

(
    tar -czf "$WORK/symlink-target.tar.gz" -C "$WORK/standard" tlbb
    ln -s "$WORK/existing/game" "$WORK/linked-target"
    expect_failure "$WORK/symlink-target.tar.gz" "$WORK/linked-target" "$WORK/backups"
    [ -L "$WORK/linked-target" ]
)
echo 'PASS: symlink deployment targets are rejected without changing their contents'

command -v zip >/dev/null
command -v unzip >/dev/null
for layout in standard flat nested; do
    case "$layout" in
        standard) input="$WORK/standard";;
        *) input="$WORK/$layout input";;
    esac
    (cd "$input"; zip -qr "$WORK/$layout.zip" .)
    untar_deploy "$WORK/$layout.zip" "$WORK/zip-$layout/game" "$WORK/backups" > "$WORK/zip-$layout.log"
    [ -f "$WORK/zip-$layout/game/Server/Config/ServerInfo.ini" ]
done
printf broken > "$WORK/broken.zip"
expect_failure "$WORK/broken.zip" "$WORK/existing/game" "$WORK/backups"
echo 'PASS: real ZIP extraction supports standard, flat and nested layouts; broken ZIP fails honestly'

source "$ROOT/cmd/color.sh"
[[ "$GSISSUE" == *https://gitee.com/yulinzhihou/gstlenv_non_docker/issues* ]]
! grep -Rq 'gstlenv/issues' "$ROOT/cmd"
echo 'PASS: all command error-report links point to the native project'
echo 'All archive deployment checks passed.'
