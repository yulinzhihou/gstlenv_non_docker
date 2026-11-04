#!/usr/bin/env bash
# Only in a disposable Linux container mounted at /work.
set -euo pipefail
[ -f /.dockerenv ] && [ "${TLBB_TEST_ALLOW_INSTALL:-0}" = 1 ] || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin
same_content() {
    local first second
    first=$(sha256sum "$1")
    second=$(sha256sum "$2")
    [ "${first%% *}" = "${second%% *}" ]
}
mkdir -p /root/.gs /tmp/gs-project/cmd /tmp/upcmd-remote/repository/cmd
printf 'GS_PROJECT=/tmp/gs-project\nTLBB_PATH=/tlgame/tlbb\n' > /root/.gs/.env
cp /root/.gs/.env /tmp/env-before
cp /work/cmd/*.sh /tmp/upcmd-remote/repository/cmd/
tar -czf /tmp/remote-commands.tar.gz -C /tmp/upcmd-remote repository
for file in /work/cmd/*.sh; do
    name="${file##*/}"
    printf '#!/usr/bin/env bash\necho "stale command"\n' > "/tmp/gs-project/cmd/$name"
    cp "/tmp/gs-project/cmd/$name" "/usr/local/bin/${name%.sh}"
    chmod +x "/usr/local/bin/${name%.sh}"
done
untar > /tmp/old-untar.log
grep -q 'stale command' /tmp/old-untar.log
[ ! -d /tlgame/tlbb ]
# Start the new updater from its installed location so it also replaces itself.
cp /work/cmd/upcmd.sh /usr/local/bin/upcmd
curl() {
    local output=""
    printf '%s\n' "$*" >> /tmp/update-requests
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -o ]; then output="$2"; break; fi
        shift
    done
    [ -n "$output" ] && cp /tmp/remote-commands.tar.gz "$output"
}
wget() { return 1; }
export -f curl wget
upcmd > /tmp/upcmd-online.log
grep -q '在线命令更新成功' /tmp/upcmd-online.log
grep -q 'untar SHA256:' /tmp/upcmd-online.log
for file in /work/cmd/*.sh; do
    name="${file##*/}"
    same_content "$file" "/tmp/gs-project/cmd/$name"
    same_content "$file" "/usr/local/bin/${name%.sh}"
done
same_content /tmp/env-before /root/.gs/.env
echo 'PASS: actual online updater replaces stale local commands and itself without changing .env'

mkdir -p /tmp/game-upload/tlbb/Server/Config
for file in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
    printf '[System]\nDBIP=fixture\n' > "/tmp/game-upload/tlbb/Server/Config/$file"
done
tar -czf /root/tlbb.tar.gz -C /tmp/game-upload tlbb
untar > /tmp/new-untar.log
grep -qx '服务端目录: /tlgame/tlbb' /tmp/new-untar.log
[ -f /tlgame/tlbb/Server/Config/LoginInfo.ini ]
[ ! -f /root/tlbb.tar.gz ]
echo 'PASS: untar after upcmd really deploys the uploaded archive into /tlgame/tlbb'

requests=$(wc -l < /tmp/update-requests)
upcmd --local > /tmp/upcmd-local.log
grep -q '本地命令重部署成功' /tmp/upcmd-local.log
! grep -q '在线命令更新成功' /tmp/upcmd-local.log
[ "$(wc -l < /tmp/update-requests)" = "$requests" ]
curl() { return 22; }
export -f curl
before=$(sha256sum /usr/local/bin/untar /tmp/gs-project/cmd/untar.sh)
if upcmd > /tmp/upcmd-failure.log 2>&1; then exit 1; fi
[ "$(sha256sum /usr/local/bin/untar /tmp/gs-project/cmd/untar.sh)" = "$before" ]
! grep -q '在线命令更新成功' /tmp/upcmd-failure.log
grep -q '未使用本机旧源码冒充更新' /tmp/upcmd-failure.log
echo 'PASS: explicit local redeployment does not download; failed online update preserves installed commands and reports failure'

exec 8>/usr/local/bin/.gs-upcmd.lock
flock -n 8
if upcmd --local > /tmp/upcmd-locked.log 2>&1; then exit 1; fi
grep -q '另一命令更新正在进行' /tmp/upcmd-locked.log
flock -u 8
exec 8>&-
echo 'PASS: concurrent command updates are rejected'

mkdir -p /tmp/shadow
cp /usr/local/bin/untar /tmp/shadow/untar
PATH=/tmp/shadow:$PATH upcmd --local > /tmp/upcmd-shadow.log 2>&1
grep -q '当前 PATH 首选 untar 为 /tmp/shadow/untar' /tmp/upcmd-shadow.log
echo 'PASS: PATH shadowing is reported with the installed absolute command path'

printf '#!/bin/sh\nexit 1\n' > /usr/local/bin/upcmd
if bash /work/cmd/gsfix.sh > /tmp/gsfix-failed.log 2>&1; then exit 1; fi
grep -q '命令重部署失败' /tmp/gsfix-failed.log
! grep -q '环境修复完成' /tmp/gsfix-failed.log
echo 'PASS: gsfix propagates command redeployment failure'
echo 'Command update smoke test passed.'
