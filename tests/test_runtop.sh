#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
PIDS=()
cleanup() {
    local pid
    for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
    rm -rf -- "$WORK"
}
trap cleanup EXIT
trap 'rc=$?; printf "FAIL: runtop test at line %s\n" "$LINENO" >&2; if [ -f "$WORK/snapshot" ]; then cat "$WORK/snapshot" >&2; fi; exit "$rc"' ERR
source "$ROOT/cmd/runtop.sh"
declare -a RUNTOP_NAMES=() RUNTOP_PATHS=()
declare -A RUNTOP_INDEX=() RUNTOP_VARS=()
game="$WORK/game with spaces"
mkdir -p "$game/Server" "$game/extra" "$game/billing" "$WORK/other"
cat > "$game/run.sh" <<'RUN'
#!/bin/bash
# ./CommentedOut &
echo "do not monitor ./EchoText"
export GAME="$TLBB_PATH/Server"
cd "$GAME"
./shm clear
./shm start
nohup ./ShareMemory >/dev/null 2>&1 &
nice -n 5 ./Login &
env LIBRARY=value ./World &
./Server &
./Missing &
(cd ../extra && ./Agent&)
(cd ../extra; ./Agent)
./Second &
cd "$TLBB_PATH/billing" && ./billing stop
./billing up -d
RUN
runtop_load_targets "$game/run.sh" "$game"
[ "${RUNTOP_NAMES[*]}" = 'ShareMemory Login World Server Missing Agent Second billing' ]
[ "${RUNTOP_PATHS[0]}" = "$game/Server/ShareMemory" ]
[ "${RUNTOP_PATHS[5]}" = "$game/extra/Agent" ]
[ "${RUNTOP_PATHS[6]}" = "$game/Server/Second" ]
[ "${RUNTOP_PATHS[7]}" = "$game/billing/billing" ]
[ "$RUNTOP_WARNINGS" = 0 ]
echo 'PASS: direct startup parsing, wrappers, comments, variables, subshell cd, billing and shm clear/start deduplication'

printf 'cd "$TLBB_PATH/Server"\r\nnohup \\\r\n ./Server >out.log 2>&1 &\r\n' > "$game/run.sh"
runtop_load_targets "$game/run.sh" "$game"
[ "${RUNTOP_NAMES[*]}" = Server ]
cat > "$game/run.sh" <<'RUN'
cd "$TLBB_PATH/Server"
./Server
cd 'literal$DIR' && ./Literal
cd "$TLBB_PATH/Server/literal\$DIR" && ./Escaped
RUN
runtop_load_targets "$game/run.sh" "$game"
[ "${RUNTOP_PATHS[1]}" = "$game/Server/literal\$DIR/Literal" ]
[ "${RUNTOP_PATHS[2]}" = "$game/Server/literal\$DIR/Escaped" ]
echo 'PASS: Windows line endings, continuations, quoted paths and literal single-quoted dollars'

cat > "$game/run.sh" <<RUN
touch "$WORK/SHOULD_NOT_EXIST"
cd "\$(touch "$WORK/SUBSTITUTION"; echo /tmp)"
./Ignored
cd "\$TLBB_PATH/Server" && ./Server
bash -c 'touch "$WORK/SHELL_C"'
source "$WORK/not-sourced"
RUN
runtop_load_targets "$game/run.sh" "$game"
[ "${RUNTOP_NAMES[*]}" = Server ]
[ "$RUNTOP_WARNINGS" -ge 2 ]
[ ! -e "$WORK/SHOULD_NOT_EXIST" ]
[ ! -e "$WORK/SUBSTITUTION" ]
[ ! -e "$WORK/SHELL_C" ]
cat > "$game/run.sh" <<'RUN'
cat <<'EOF'
./NotAProcess
EOF
RUN
if runtop_load_targets "$game/run.sh" "$game" > "$WORK/error" 2>&1; then exit 1; fi
grep -q 'here-document' "$WORK/error"
printf '#!/bin/bash\nsleep 1\n' > "$game/run.sh"
if runtop_load_targets "$game/run.sh" "$game" > "$WORK/error" 2>&1; then exit 1; fi
grep -q '未识别' "$WORK/error"
if runtop_load_targets "$game/not-found" "$game" > "$WORK/error" 2>&1; then exit 1; fi
grep -q '无法读取' "$WORK/error"
echo 'PASS: inspection never executes shell text; unsupported and empty startup scripts fail honestly'

# Some minimal EL images implement sleep/yes as multicall scripts. Use the
# native Bash executable so /proc/PID/exe really points at each fixture path.
cp "$(command -v bash)" "$game/Server/Server"
cp "$(command -v bash)" "$game/Server/Login"
cp "$(command -v bash)" "$game/Server/Busy"
cp "$(command -v bash)" "$WORK/other/Server"
mkfifo "$WORK/wait"
exec 3<> "$WORK/wait"
cat > "$game/Server/Worker.sh" <<'WORKER'
#!/bin/bash
read -r -t 60 -u 3 || :
WORKER
chmod +x "$game/Server/Worker.sh"
ln -s Server "$game/Server/Alias"
cat > "$game/run.sh" <<'RUN'
cd "$TLBB_PATH/Server"
./Alias 60 &
./Login 60 &
./Busy &
./Worker.sh &
./Missing &
RUN
"$game/Server/Server" -c 'read -r -t 60 -u 3 || :' & PIDS+=("$!")
"$game/Server/Server" -c 'read -r -t 60 -u 3 || :' & PIDS+=("$!")
"$WORK/other/Server" -c 'read -r -t 60 -u 3 || :' & PIDS+=("$!")
"$game/Server/Busy" -c 'while :; do :; done' & PIDS+=("$!")
"$game/Server/Worker.sh" & PIDS+=("$!")
sleep 0.1
runtop_watch "$game" 1 2 > "$WORK/snapshot"
grep -Eq "^Server +RUN/[RS] +${PIDS[0]} " "$WORK/snapshot"
grep -Eq "^Server +RUN/[RS] +${PIDS[1]} " "$WORK/snapshot"
! grep -Eq "^Server +RUN/[^ ]+ +${PIDS[2]} " "$WORK/snapshot"
grep -Eq '^Login +STOP ' "$WORK/snapshot"
grep -Eq '^Missing +MISSING ' "$WORK/snapshot"
grep -Eq "^Worker.sh +RUN/[RS] +${PIDS[4]} " "$WORK/snapshot"
awk '$1 == "Busy" && $4 + 0 > 0 && $6 + 0 > 0 {found=1} END {exit !found}' "$WORK/snapshot"
[ "$(grep -c '^GS游享网' "$WORK/snapshot")" = 1 ]
! grep -q $'\033' "$WORK/snapshot"
runtop_watch "$game" 0 2 < /dev/null > "$WORK/piped"
[ "$(grep -c '^GS游享网' "$WORK/piped")" = 1 ]
kill "${PIDS[0]}"; wait "${PIDS[0]}" || true
runtop_watch "$game" 1 2 > "$WORK/restarted"
! grep -Eq "^Server +RUN/[^ ]+ +${PIDS[0]} " "$WORK/restarted"
grep -Eq "^Server +RUN/[RS] +${PIDS[1]} " "$WORK/restarted"
echo 'PASS: live /proc sampling, interval CPU, RSS, symlinks, script processes, duplicate PIDs, stopped/missing states and unrelated-process exclusion'

bash "$ROOT/cmd/runtop.sh" --help > "$WORK/help"
grep -q -- '--once' "$WORK/help"
for args in '--interval' '--interval 0' '--interval 61' '--interval 1.5' '--interval nope' '--unknown'; do
    read -r -a argv <<< "$args"
    if bash "$ROOT/cmd/runtop.sh" "${argv[@]}" > "$WORK/invalid" 2>&1; then exit 1; fi
done
echo 'PASS: help and invalid CLI arguments'

if command -v python3 >/dev/null 2>&1; then
    python3 "$ROOT/tests/test_runtop_pty.py" "$ROOT/cmd/runtop.sh" "$game"
else
    echo 'SKIP: terminal interaction checks need python3 (monitor itself does not)'
fi
echo 'All runtop checks passed.'
