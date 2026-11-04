#!/usr/bin/env bash
# Only in a disposable Linux container mounted at /work.
set -euo pipefail
[ -f /.dockerenv ] && [ "${TLBB_TEST_ALLOW_INSTALL:-0}" = 1 ] || exit 1
mkdir -p /root/.gs /tmp/archive-fixture/wrapper/tlbb2/Server/Config /tmp/gs-project
printf 'TLBB_PATH=/tlgame/tlbb\nGS_PROJECT=/tmp/gs-project\n' > /root/.gs/.env
cp -a /work/assets /tmp/gs-project/assets
cp /work/cmd/color.sh /usr/local/bin/color
for file in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
    printf '[System]\nDBIP=old\n' > "/tmp/archive-fixture/wrapper/tlbb2/Server/Config/$file"
done
tar -czf /root/tlbb.tar.gz -C /tmp/archive-fixture .
bash /work/cmd/untar.sh > /tmp/untar.log
[ -f /tlgame/tlbb/Server/Config/LoginInfo.ini ]
grep -qx '服务端目录: /tlgame/tlbb' /tmp/untar.log
[ ! -f /root/tlbb.tar.gz ]
echo 'PASS: actual untar command deploys /root/tlbb.tar.gz into /tlgame/tlbb on a clean host'

mv /tlgame/tlbb/Server/Config/LoginInfo.ini /tmp/saved-LoginInfo.ini
if bash /work/cmd/setini.sh > /tmp/setini-missing-file.log 2>&1; then exit 1; fi
grep -q '/tlgame/tlbb/Server/Config/LoginInfo.ini' /tmp/setini-missing-file.log
grep -q 'gstlenv_non_docker/issues' /tmp/setini-missing-file.log
[ ! -f /tmp/gs-project/config/tmp1 ]
mv /tmp/saved-LoginInfo.ini /tlgame/tlbb/Server/Config/LoginInfo.ini
printf 'TLBB_PATH=/custom/missing-game\nGS_PROJECT=/tmp/gs-project\n' > /root/.gs/.env
if bash /work/cmd/setini.sh > /tmp/setini-missing-dir.log 2>&1; then exit 1; fi
grep -q '/custom/missing-game/Server/Config' /tmp/setini-missing-dir.log
! grep -q 'gstlenv/issues' /tmp/setini-missing-dir.log
echo 'PASS: actual setini command reports configured paths and native issue link before modifying configuration'

printf 'TLBB_PATH=/tlgame/tlbb\nGS_PROJECT=/tmp/gs-project\nTL_MYSQL_PASSWORD=fixture-only\n' > /root/.gs/.env
cp /work/cmd/untar.sh /usr/local/bin/untar
cp /work/cmd/billing-env.sh /usr/local/bin/billing-env
chmod +x /usr/local/bin/untar
sleep() { :; }
mysqladmin() { return 1; }
mysql() { echo unexpected >> /tmp/unexpected-sql; }
setini() { echo unexpected >> /tmp/unexpected-setini; }
runtlbb() { echo unexpected >> /tmp/unexpected-start; }
export -f sleep mysqladmin mysql setini runtlbb
# The successful extraction renamed the upload, so change's untar must fail.
if printf 'y\n' | bash /work/cmd/change.sh > /tmp/change-failure.log 2>&1; then exit 1; fi
grep -q '不重置数据库' /tmp/change-failure.log
[ ! -e /tmp/unexpected-sql ]
[ ! -e /tmp/unexpected-setini ]
[ ! -e /tmp/unexpected-start ]
[ -f /tlgame/tlbb/Server/Config/LoginInfo.ini ]
echo 'PASS: actual change command stops after untar failure without resetting SQL, rewriting config or starting the game'
echo 'Archive command smoke test passed.'
