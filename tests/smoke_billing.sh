#!/usr/bin/env bash
# Only in a disposable Linux container mounted at /work; no user game/binary is run.
set -euo pipefail
[ -f /.dockerenv ] && [ "${TLBB_TEST_ALLOW_INSTALL:-0}" = 1 ] || exit 1
mkdir -p /root/.gs /tmp/gs-project /tmp/upload/tlbb/Server/Config
cp -a /work/assets /tmp/gs-project/assets
for file in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
    printf '[System]\nDBIP=old\nDBPort=0\nDBName=old\nDBUser=old\nDBPassword=old\n' > "/tmp/upload/tlbb/Server/Config/$file"
done
printf '#!/bin/bash\ntrue\n' > /tmp/upload/tlbb/run.sh
printf 'GS_PROJECT=/tmp/gs-project\nTLBB_PATH=/tlgame/tlbb\nTLBB_ODBC_DRIVER=/tmp/test-driver.so\n' > /root/.gs/.env
printf '%s\n' "TLBB_MYSQL_PASSWORD='!Ab:c#dE12+f='" >> /root/.gs/.env
touch /tmp/test-driver.so
tar -czf /root/tlbb.tar.gz -C /tmp/upload tlbb
bash /work/cmd/untar.sh > /tmp/untar-billing.log
[ -f /tlgame/tlbb/Server/Config/LoginInfo.ini ]
[ -L /home/billing ]
[ -x /home/billing/billing ]
grep -q '环境内置 64 位程序' /tmp/untar-billing.log
grep -q '【setini】.*【upgm】.*【runtlbb】' /tmp/untar-billing.log
bash /work/cmd/setini.sh > /tmp/setini-billing.log
grep -q 'Billing 程序及配置已就绪' /tmp/setini-billing.log
grep -Fqx "db_password: '!Ab:c#dE12+f='" /home/billing/config.yaml
[ "$(stat -c %a /home/billing/config.yaml)" = 600 ]
[ "$(stat -c %a /tmp/gs-project/config/config.yaml)" = 600 ]
[ "$(stat -c %a /home/billing/billing)" = 755 ]
! grep -q '!Ab:c#dE12+f=' /tmp/setini-billing.log
echo 'PASS: actual untar/setini deploy built-in Billing, display the complete next steps and write private, quoted runtime credentials'

mkdir -p /tmp/billing-upload/wrapper/billing
cp /work/assets/billing/billing64 /tmp/billing-upload/wrapper/billing/billing
# A distinct ELF payload for deployment checks only; never execute this fixture.
printf '\nfixture-upload-marker\n' >> /tmp/billing-upload/wrapper/billing/billing
printf 'db_password: should-not-be-used\n' > /tmp/billing-upload/wrapper/billing/config.yaml
tar -czf /root/billing.tar.gz -C /tmp/billing-upload .
before=$(sha256sum /root/billing.tar.gz)
bash /work/cmd/setini.sh > /tmp/setini-upload.log
new=$(sha256sum /home/billing/billing)
expected=$(sha256sum /tmp/billing-upload/wrapper/billing/billing)
[ "${new%% *}" = "${expected%% *}" ]
[ "$before" = "$(sha256sum /root/billing.tar.gz)" ]
grep -q '上传包 /root/billing.tar.gz' /tmp/setini-upload.log
grep -Fqx "db_password: '!Ab:c#dE12+f='" /home/billing/config.yaml
grep -Fqx 'cd /home/billing && ./billing up -d' /tlgame/tlbb/run.sh
bash /work/cmd/setini.sh > /tmp/setini-rerun.log
[ "$(grep -Fc 'cd /home/billing && ./billing up -d' /tlgame/tlbb/run.sh)" = 1 ]
printf 'TLBB_MYSQL_PASSWORD=%q\n' "a'!b:c#D12+E=" >> /root/.gs/.env
bash /work/cmd/setini.sh > /tmp/setini-quoted.log
grep -Fqx "db_password: 'a''!b:c#D12+E='" /home/billing/config.yaml
echo 'PASS: setini alone applies root upload priority without re-extracting the game; packaged default credentials are ignored and startup line stays unique'

before=$(sha256sum /home/billing/billing /home/billing/config.yaml)
printf broken > /root/billing.tar.gz
if bash /work/cmd/setini.sh > /tmp/setini-invalid.log 2>&1; then exit 1; fi
[ "$before" = "$(sha256sum /home/billing/billing /home/billing/config.yaml)" ]
! grep -q '配置文件已经写入成功' /tmp/setini-invalid.log
echo 'PASS: invalid preferred root upload cannot fall back silently or claim configuration success'

printf 'IS_DLQ=1\n' >> /root/.gs/.env
bash /work/cmd/setini.sh > /tmp/setini-remote.log
grep -q 'W机验证模式: 不部署或启动本机 Billing' /tmp/setini-remote.log
echo 'PASS: remote W-machine verification mode does not require or deploy a local Billing executable'
echo 'Billing command smoke test passed.'
