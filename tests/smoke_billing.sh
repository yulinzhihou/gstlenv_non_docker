#!/usr/bin/env bash
# Only in a disposable Linux container mounted at /work; no user game/binary is run.
set -euo pipefail
[ -f /.dockerenv ] && [ "${TLBB_TEST_ALLOW_INSTALL:-0}" = 1 ] || exit 1
mkdir -p /root/.gs /tmp/gs-project /tmp/upload/tlbb/Server/Config
cp -a /work/assets /tmp/gs-project/assets
for file in ServerInfo.ini LoginInfo.ini ShareMemInfo.ini; do
    printf '[System]\nDBIP=old\nDBPort=0\nDBName=old\nDBUser=old\nDBPassword=old\n' > "/tmp/upload/tlbb/Server/Config/$file"
done
cp /work/tests/fixtures/run-legacy.sh /tmp/upload/tlbb/run.sh
for file in shm ShareMemory Login World Server_fix; do cp /bin/bash "/tmp/upload/tlbb/Server/$file"; done
touch /tmp/upload/tlbb/Server/Serverhook.so
printf 'GS_PROJECT=/tmp/gs-project\nTLBB_PATH=/tlgame/tlbb\nTLBB_ODBC_DRIVER=/tmp/test-driver.so\n' > /root/.gs/.env
printf '%s\n' "TLBB_MYSQL_PASSWORD='!Ab:c#dE12+f='" >> /root/.gs/.env
touch /tmp/test-driver.so
tar -czf /root/tlbb.tar.gz -C /tmp/upload tlbb
bash /work/cmd/untar.sh > /tmp/untar-billing.log
[ -f /tlgame/tlbb/Server/Config/LoginInfo.ini ]
[ ! -e /home/billing ]
[ -d /tlgame/billing ] && [ ! -L /tlgame/billing ]
[ -x /tlgame/billing/billing ]
! grep -q '/home/tlbb\|/home/billing' /tlgame/tlbb/run.sh
grep -q '环境内置 64 位程序' /tmp/untar-billing.log
grep -q '【setini】.*【upgm】.*【runtlbb】' /tmp/untar-billing.log
bash /work/cmd/setini.sh > /tmp/setini-billing.log
grep -q 'Billing 程序及配置已就绪' /tmp/setini-billing.log
grep -Fqx "db_password: '!Ab:c#dE12+f='" /tlgame/billing/config.yaml
[ "$(stat -c %a /tlgame/billing/config.yaml)" = 600 ]
[ "$(stat -c %a /tmp/gs-project/config/config.yaml)" = 600 ]
[ "$(stat -c %a /tlgame/billing/billing)" = 755 ]
! grep -q '!Ab:c#dE12+f=' /tmp/setini-billing.log
bash /work/cmd/step.sh --list > /tmp/step-list.log
grep -q 'step 1  \[Billing / billing\]' /tmp/step-list.log
grep -q 'step 2  \[ShareMemory / shm\]' /tmp/step-list.log
grep -q 'step 3  \[Login / Login\]' /tmp/step-list.log
grep -q 'step 4  \[World / World\]' /tmp/step-list.log
grep -q 'step 5  \[Server / Server_fix\]' /tmp/step-list.log
grep -q 'setarch x86_64 -R env LD_PRELOAD=' /tmp/step-list.log
bash /work/cmd/step.sh --check > /tmp/step-check.log
bash /work/cmd/runtop.sh --once > /tmp/runtop-check.log
grep -Eq '^Server_fix +STOP ' /tmp/runtop-check.log
echo 'PASS: actual untar/setini deploy built-in Billing, display the complete next steps and write private, quoted runtime credentials'

before=$(sha256sum /tlgame/billing/config.yaml /etc/odbc.ini /tlgame/tlbb/Server/Config/*.ini)
mv /tlgame/tlbb/Server/Server_fix /tmp/saved-Server_fix
if bash /work/cmd/setini.sh > /tmp/setini-bad-program.log 2>&1; then exit 1; fi
grep -q '程序不存在或不可执行: /tlgame/tlbb/Server/Server_fix' /tmp/setini-bad-program.log
grep -q '请修复.*run.sh' /tmp/setini-bad-program.log
[ "$before" = "$(sha256sum /tlgame/billing/config.yaml /etc/odbc.ini /tlgame/tlbb/Server/Config/*.ini)" ]
! grep -q '配置文件已经写入成功' /tmp/setini-bad-program.log
mv /tmp/saved-Server_fix /tlgame/tlbb/Server/Server_fix
mv /tlgame/tlbb/Server/Serverhook.so /tmp/saved-Serverhook.so
if bash /work/cmd/setini.sh > /tmp/setini-bad-hook.log 2>&1; then exit 1; fi
grep -q 'LD_PRELOAD.*Serverhook.so' /tmp/setini-bad-hook.log
[ "$before" = "$(sha256sum /tlgame/billing/config.yaml /etc/odbc.ini /tlgame/tlbb/Server/Config/*.ini)" ]
mv /tmp/saved-Serverhook.so /tlgame/tlbb/Server/Serverhook.so
echo 'PASS: real setini blocks missing programs/hooks before changing INI/ODBC/Billing configuration; step and runtop agree about Server_fix'

mkdir -p /tmp/billing-upload/wrapper/billing
cp /work/assets/billing/billing64 /tmp/billing-upload/wrapper/billing/billing
# A distinct ELF payload for deployment checks only; never execute this fixture.
printf '\nfixture-upload-marker\n' >> /tmp/billing-upload/wrapper/billing/billing
printf 'db_password: should-not-be-used\n' > /tmp/billing-upload/wrapper/billing/config.yaml
tar -czf /root/billing.tar.gz -C /tmp/billing-upload .
before=$(sha256sum /root/billing.tar.gz)
bash /work/cmd/setini.sh > /tmp/setini-upload.log
new=$(sha256sum /tlgame/billing/billing)
expected=$(sha256sum /tmp/billing-upload/wrapper/billing/billing)
[ "${new%% *}" = "${expected%% *}" ]
[ "$before" = "$(sha256sum /root/billing.tar.gz)" ]
grep -q '上传包 /root/billing.tar.gz' /tmp/setini-upload.log
grep -Fqx "db_password: '!Ab:c#dE12+f='" /tlgame/billing/config.yaml
bash /work/cmd/setini.sh > /tmp/setini-rerun.log
[ "$(grep -c 'billing up -d' /tlgame/tlbb/run.sh)" = 2 ]
printf 'TLBB_MYSQL_PASSWORD=%q\n' "a'!b:c#D12+E=" >> /root/.gs/.env
bash /work/cmd/setini.sh > /tmp/setini-quoted.log
grep -Fqx "db_password: 'a''!b:c#D12+E='" /tlgame/billing/config.yaml
echo 'PASS: setini alone applies root upload priority without re-extracting the game; packaged default credentials are ignored and startup line stays unique'

before=$(sha256sum /tlgame/billing/billing /tlgame/billing/config.yaml)
printf broken > /root/billing.tar.gz
if bash /work/cmd/setini.sh > /tmp/setini-invalid.log 2>&1; then exit 1; fi
[ "$before" = "$(sha256sum /tlgame/billing/billing /tlgame/billing/config.yaml)" ]
! grep -q '配置文件已经写入成功' /tmp/setini-invalid.log
echo 'PASS: invalid preferred root upload cannot fall back silently or claim configuration success'

printf 'IS_DLQ=1\n' >> /root/.gs/.env
if bash /work/cmd/setini.sh > /tmp/setini-remote-local-billing.log 2>&1; then exit 1; fi
grep -q 'W机验证模式不应启动本机 Billing' /tmp/setini-remote-local-billing.log
# Removing explicit local Billing starts is a user action in W-machine mode.
sed -i '/cd \/tlgame\/billing/d; /\.\/billing up -d/d' /tlgame/tlbb/run.sh
bash /work/cmd/setini.sh > /tmp/setini-remote.log
grep -q 'W机验证模式: 不部署或启动本机 Billing' /tmp/setini-remote.log
echo 'PASS: remote W-machine verification mode does not require or deploy a local Billing executable'

cat > /tlgame/tlbb/run.sh <<'RUN'
#!/bin/bash
cd "$TLBB_PATH/Server" || exit 1
./Server_fix
RUN
cat > /tlgame/tlbb/Server/Server_fix <<'PROGRAM'
#!/bin/bash
printf '%s\n' "$PWD" > /tmp/actual-start-cwd
PROGRAM
chmod 755 /tlgame/tlbb/Server/Server_fix
mysqladmin() { printf called > /tmp/mysqladmin-called; }
export -f mysqladmin
mv /tlgame/tlbb/Server/Server_fix /tmp/start-program
if bash /work/cmd/runtlbb.sh > /tmp/start-missing.log 2>&1; then exit 1; fi
[ ! -e /tmp/actual-start-cwd ] && [ ! -e /tmp/mysqladmin-called ]
mv /tmp/start-program /tlgame/tlbb/Server/Server_fix
bash /work/cmd/runtlbb.sh > /tmp/start-valid.log
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ ! -e /tmp/actual-start-cwd ] || break
    sleep 0.1
done
grep -qx '/tlgame/tlbb/Server' /tmp/actual-start-cwd
grep -q '已提交 run.sh 后台启动请求' /tmp/start-valid.log
echo 'PASS: actual runtlbb preflight blocks missing programs and passes canonical path variables to a harmless background startup fixture'
echo 'Billing command smoke test passed.'
