#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
source "$ROOT/cmd/billing-env.sh"

fixture() {
    case_dir="$WORK/$1"
    mkdir -p "$case_dir"
}
prepare() {
    billing_prepare "$ROOT" "$case_dir/data/billing" "$case_dir/home/billing" \
        "$case_dir/billing.tar.gz" "$case_dir/backups"
}
same() { cmp "$1" "$2"; }
upload() {
    local layout="$1"
    mkdir -p "$case_dir/input/$layout"
    cp "$ROOT/assets/billing/billing64" "$case_dir/input/$layout/billing"
    printf 'db_password: do-not-install\n' > "$case_dir/input/$layout/config.yaml"
    tar -czf "$case_dir/billing.tar.gz" -C "$case_dir/input" .
}
failed_unchanged() {
    local before
    before=$(sha256sum "$case_dir/home/billing/billing" "$case_dir/home/billing/config.yaml")
    if prepare > "$case_dir/failed.log" 2>&1; then exit 1; fi
    [ "$(sha256sum "$case_dir/home/billing/billing" "$case_dir/home/billing/config.yaml")" = "$before" ]
    ! grep -q 'Billing 程序已就绪' "$case_dir/failed.log"
}

fixture 'fresh paths with spaces'
prepare > "$case_dir/first.log"
[ -L "$case_dir/home/billing" ]
[ "$(readlink "$case_dir/home/billing")" = "$case_dir/data/billing" ]
same "$ROOT/assets/billing/billing64" "$case_dir/home/billing/billing"
[ "$(stat -c %a "$case_dir/home/billing/billing")" = 755 ]
printf preserved > "$case_dir/home/billing/config.yaml"
printf old-log > "$case_dir/home/billing/log.log"
prepare > "$case_dir/second.log"
grep -q '已有程序' "$case_dir/second.log"
[ ! -d "$case_dir/backups" ]
[ "$(<"$case_dir/home/billing/config.yaml")" = preserved ]
[ "$(<"$case_dir/home/billing/log.log")" = old-log ]
echo 'PASS: native bundled deployment creates the compatibility link; rerun preserves config/logs without redundant backups'

for layout in flat nested; do
    fixture "$layout-upload"
    mkdir -p "$case_dir/home/billing"
    cp "$ROOT/assets/billing/billing32" "$case_dir/home/billing/billing"
    printf preserved > "$case_dir/home/billing/config.yaml"
    upload "$layout"
    archive_before=$(sha256sum "$case_dir/billing.tar.gz")
    prepare > "$case_dir/updated.log"
    same "$ROOT/assets/billing/billing64" "$case_dir/home/billing/billing"
    [ "$archive_before" = "$(sha256sum "$case_dir/billing.tar.gz")" ]
    [ "$(<"$case_dir/home/billing/config.yaml")" = preserved ]
    backup=$(find "$case_dir/backups" -name 'billing-before-*' -type f)
    same "$ROOT/assets/billing/billing32" "$backup"
    grep -q '上传包 .*优先' "$case_dir/updated.log"
done
echo 'PASS: flat/nested root uploads override an existing program, retain the archive, back up the old executable and ignore packaged credentials'

fixture legacy-nested-link
mkdir -p "$case_dir/home/billing" "$case_dir/data/billing"
cp "$ROOT/assets/billing/billing64" "$case_dir/data/billing/billing"
ln -s "$case_dir/data/billing" "$case_dir/home/billing/billing"
printf preserved > "$case_dir/home/billing/config.yaml"
prepare > "$case_dir/repair.log"
[ ! -L "$case_dir/home/billing/billing" ]
same "$ROOT/assets/billing/billing64" "$case_dir/home/billing/billing"
[ "$(<"$case_dir/home/billing/config.yaml")" = preserved ]
[ -L "$(find "$case_dir/backups" -name 'billing-before-*')" ]
echo 'PASS: the former nested directory link is repaired without deleting either directory or its configuration'

fixture failures
prepare > /dev/null
printf preserved > "$case_dir/home/billing/config.yaml"
printf broken > "$case_dir/billing.tar.gz"
failed_unchanged
upload good
tar -czf "$case_dir/billing.tar.gz" --transform='s|^|../|' -C "$case_dir/input" .
failed_unchanged
rm -rf "$case_dir/input"
mkdir -p "$case_dir/input/one" "$case_dir/input/two"
cp "$ROOT/assets/billing/billing64" "$case_dir/input/one/billing"
cp "$ROOT/assets/billing/billing64" "$case_dir/input/two/billing"
tar -czf "$case_dir/billing.tar.gz" -C "$case_dir/input" .
failed_unchanged
rm -rf "$case_dir/input"
mkdir "$case_dir/input"
ln -s "$ROOT/assets/billing/billing64" "$case_dir/input/billing"
tar -czf "$case_dir/billing.tar.gz" -C "$case_dir/input" .
failed_unchanged
rm "$case_dir/input/billing"
cp "$ROOT/assets/billing/billing32" "$case_dir/input/billing"
tar -czf "$case_dir/billing.tar.gz" -C "$case_dir/input" .
failed_unchanged
echo 'PASS: corrupt, traversal, ambiguous, symlinked and wrong-architecture uploads fail without changing the old binary/config'

(
    fixture host32
    uname() { printf 'i686\n'; }
    prepare > "$case_dir/host32.log"
    same "$ROOT/assets/billing/billing32" "$case_dir/home/billing/billing"
)
(
    fixture hostarm
    uname() { printf 'aarch64\n'; }
    if prepare > "$case_dir/hostarm.log" 2>&1; then exit 1; fi
    grep -q '无内置 arm64 程序' "$case_dir/hostarm.log"
    [ ! -f "$case_dir/home/billing/billing" ]
)
(
    fixture corrupted-bundle
    mkdir "$case_dir/project"
    cp -a "$ROOT/assets" "$case_dir/project/assets"
    printf broken >> "$case_dir/project/assets/billing/billing64"
    if billing_prepare "$case_dir/project" "$case_dir/data" "$case_dir/runtime" \
        "$case_dir/missing.tar.gz" "$case_dir/backups" > "$case_dir/corrupted.log" 2>&1; then exit 1; fi
    grep -q '内置资源缺失或校验失败' "$case_dir/corrupted.log"
)
echo 'PASS: host architecture selects 32/64-bit binaries independently of game/MySQL; unsupported hosts and corrupt built-ins are explicit failures'
echo 'All Billing deployment checks passed.'
