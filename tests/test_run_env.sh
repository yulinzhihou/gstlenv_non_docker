#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
PID=""
cleanup() {
    [ -z "$PID" ] || { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
    rm -rf -- "$WORK"
}
trap cleanup EXIT
trap 'rc=$?; echo "FAIL: run-env test at line $LINENO" >&2; exit "$rc"' ERR
source "$ROOT/cmd/run-env.sh"
source "$ROOT/cmd/step.sh"
game="$WORK/tlgame/tlbb"
billing="$WORK/tlgame/billing"
export TRACE_FILE="$WORK/trace"
mkdir -p "$game/Server" "$billing" "$WORK/backups"
cat > "$WORK/program" <<'PROGRAM'
#!/bin/bash
printf '%s|%s|%s|%s|%s\n' "${0##*/}" "$PWD" "${LD_LIBRARY_PATH-}" "${ASAN_OPTIONS-unset}" "$*" >> "$TRACE_FILE"
PROGRAM
chmod 755 "$WORK/program"
for name in shm ShareMemory World Server_fix Login Center Server1; do cp "$WORK/program" "$game/Server/$name"; done
cp "$WORK/program" "$billing/billing"
touch "$game/Server/Serverhook.so" "$game/Server/exit.cmd" "$game/Server/quitserver.cmd"
cp "$ROOT/tests/fixtures/run-legacy.sh" "$game/run.sh"
cp "$game/run.sh" "$WORK/original"
run_normalize "$game/run.sh" "$game" "$billing" "$WORK/backups" > "$WORK/normalize.log"
! grep -q '/home/tlbb\|/home/billing' "$game/run.sh"
grep -Fq "LD_PRELOAD=\"$game/Server/Serverhook.so\"" "$game/run.sh"
[ "$(grep -c 'billing up -d' "$game/run.sh")" = 2 ]
backup=$(find "$WORK/backups" -type f -name 'run.sh-before-*')
before=$(sha256sum "$backup"); after=$(sha256sum "$WORK/original")
[ "${before%% *}" = "${after%% *}" ]
[ "$(stat -c %a "$backup")" = 600 ]
run_normalize "$game/run.sh" "$game" "$billing" "$WORK/backups" > "$WORK/rerun.log"
[ "$(find "$WORK/backups" -type f | wc -l)" = 1 ]
run_load "$game/run.sh" "$game"
run_validate "$game" "$billing" 1
run_order
[ "${#RUN_ORDER[@]}" = 5 ]
roles=()
for index in "${RUN_ORDER[@]}"; do roles+=("${RUN_ROLES[index]}"); done
[ "${roles[*]}" = 'Billing ShareMemory Login World Server' ]
server="${RUN_ORDER[4]}"
[ "${RUN_NAMES[server]}" = Server_fix ]
[ "${RUN_ARGS[$server,0]}" = setarch ]
[ "${RUN_ARGS[$server,1]}" = x86_64 ]
[ "${RUN_ARGS[$server,2]}" = -R ]
[ "${RUN_ARGS[$server,3]}" = env ]
[ "${RUN_ARGS[$server,4]}" = "LD_PRELOAD=$game/Server/Serverhook.so" ]
[ "${RUN_ARGS[$server,5]}" = "$game/Server/Server_fix" ]
[ "$RUN_BILLING_SEEN" = 2 ]
[ ! -f "$TRACE_FILE" ]
[ -f "$game/Server/exit.cmd" ] && [ -f "$game/Server/quitserver.cmd" ]
echo 'PASS: supplied-style guard, wrappers, stable role order, real Server_fix path, persistent exports/unsets, Billing deduplication and private idempotent path migration'

setarch() {
    printf 'setarch|%s\n' "$*" >> "$WORK/wrapper-trace"
    shift 2
    "$@"
}
env() {
    printf 'env|%s\n' "$*" >> "$WORK/wrapper-trace"
    # Assert the exact preload argument above, without loading a test .so.
    case "${1:-}" in LD_PRELOAD=*) shift;; esac
    command env "$@"
}
export ASAN_OPTIONS=must-be-unset
for number in 1 2 3 4 5; do step_run "$game" "$billing" "$number" > "$WORK/step-$number.log"; done
[ "$(cut -d '|' -f1 "$TRACE_FILE" | paste -sd ' ')" = 'billing shm Login World Server_fix' ]
grep -Fq "Server_fix|$game/Server|$game/Server:|unset|" "$TRACE_FILE"
grep -Fq "x86_64 -R env LD_PRELOAD=$game/Server/Serverhook.so" "$WORK/wrapper-trace"
[ -f "$game/Server/exit.cmd" ] && [ -f "$game/Server/quitserver.cmd" ]
echo 'PASS: step 1..5 launches exactly one harmless fixture each, retaining wrapper arguments and environment without executing original cleanup/kernel writes'

printf '\ncd "%s/Server"\n./Center --zone 6 &\n./Server1 --zone 7 &\n' "$game" >> "$game/run.sh"
step_run "$game" "$billing" --list > "$WORK/list"
grep -q 'step 6  \[Server / Server1\]' "$WORK/list"
grep -q 'step 7  \[Other / Center\]' "$WORK/list"
before=$(wc -l < "$TRACE_FILE")
for number in 0 -1 1000000 nope; do
    if step_run "$game" "$billing" "$number" > "$WORK/bad" 2>&1; then exit 1; fi
done
[ "$(wc -l < "$TRACE_FILE")" = "$before" ]
mv "$game/Server/Serverhook.so" "$WORK/hook"
if step_run "$game" "$billing" --check > "$WORK/missing-hook" 2>&1; then exit 1; fi
grep -q 'LD_PRELOAD.*Serverhook.so' "$WORK/missing-hook"
mv "$WORK/hook" "$game/Server/Serverhook.so"
mv "$game/Server/World" "$WORK/World"
if step_run "$game" "$billing" --check > "$WORK/missing-world" 2>&1; then exit 1; fi
grep -q '程序不存在或不可执行.*World' "$WORK/missing-world"
mv "$WORK/World" "$game/Server/World"
echo 'PASS: extra instances have independent steps; invalid indexes, missing binaries and missing hooks never launch a program'

cat > "$game/run.sh" <<'RUN'
#!/bin/bash
cd "$TLBB_PATH/Server"
./Login 'literal $(touch SHOULD_NOT_EXIST)' &
exit 0
RUN
run_normalize "$game/run.sh" "$game" "$billing" "$WORK/backups" > /dev/null
[ "$(sed -n '2p' "$game/run.sh")" = "(cd $billing && ./billing up -d)" ]
step_run "$game" "$billing" 2 > "$WORK/literal.log"
grep -Fq 'literal $(touch SHOULD_NOT_EXIST)' "$TRACE_FILE"
[ ! -f "$game/Server/SHOULD_NOT_EXIST" ]
echo 'PASS: missing Billing is inserted before an exit without changing cwd; quoted shell text is passed literally, never evaluated'

cat >> "$game/Server/Login" <<'WAIT'
read -r -t 60 -u 3 || :
WAIT
mkfifo "$WORK/wait"
exec 3<> "$WORK/wait"
"$game/Server/Login" & PID=$!
sleep 0.1
if step_run "$game" "$billing" 2 > "$WORK/duplicate" 2>&1; then exit 1; fi
grep -q '不重复启动或自动停止' "$WORK/duplicate"
kill "$PID"; wait "$PID" || true
PID=""
echo 'PASS: an already-running exact script path is not restarted'

cat > "$game/run.sh" <<'RUN'
#!/bin/bash
cd "$TLBB_PATH/Server"
LIBRARY=outer
export LIBRARY
(export LIBRARY=inner; unset LD_LIBRARY_PATH; ulimit -c 0; ./Server1 2>/dev/null --zone 2 &)
./Login 2>&1 --zone 3 >/dev/null &
./shm start
RUN
run_load "$game/run.sh" "$game"
[ "${RUN_NAMES[*]}" = 'Server1 Login shm' ]
[ "${RUN_ARGC[0]}" = 3 ] && [ "${RUN_ARGS[0,1]}" = --zone ] && [ "${RUN_ARGS[0,2]}" = 2 ]
[ "${RUN_ARGC[1]}" = 3 ] && [ "${RUN_ARGS[1,1]}" = --zone ] && [ "${RUN_ARGS[1,2]}" = 3 ]
[ "${RUN_UNSETC[0]}" = 1 ] && [ "${RUN_UNSETC[1]}" = 0 ]
[ "${RUN_LIMIT_C[0]}" = 0 ] && [ -z "${RUN_LIMIT_C[1]}" ]
found_inner=0; found_outer=0
for key in "${!RUN_ENV_NAMES[@]}"; do
    if [ "${RUN_ENV_NAMES[$key]}" = LIBRARY ]; then
        case "$key:${RUN_ENV_VALUES[$key]}" in
            0,*:inner) found_inner=1;;
            1,*:outer) found_outer=1;;
        esac
    fi
done
[ "$found_inner" = 1 ] && [ "$found_outer" = 1 ]
mv "$game/Server/ShareMemory" "$WORK/ShareMemory"
if run_validate "$game" "$billing" 0 > "$WORK/missing-sharememory" 2>&1; then exit 1; fi
grep -q 'shm 对应程序不存在或不可执行' "$WORK/missing-sharememory"
mv "$WORK/ShareMemory" "$game/Server/ShareMemory"
run_validate "$game" "$billing" 0
printf '\n"$UNKNOWN_PROGRAM" &\n' >> "$game/run.sh"
run_load "$game/run.sh" "$game"
if run_validate "$game" "$billing" 0 > "$WORK/unknown-program" 2>&1; then exit 1; fi
grep -q '程序路径含未解析变量' "$WORK/unknown-program"
echo 'PASS: subshell exports/unsets/limits stay scoped; redirections do not change argv; missing ShareMemory and unresolved executable variables fail preflight'

cat > "$game/run.sh" <<'RUN'
#!/bin/bash
cd "$TLBB_PATH/Server"
if ps aux | grep './Login' >/dev/null; then ./Login --zone 3 & fi
./Server1 | tee /tmp/not-opened
RUN
run_load "$game/run.sh" "$game"
[ "${RUN_NAMES[*]}" = 'Login Server1' ]
if run_validate "$game" "$billing" 0 > "$WORK/pipeline" 2>&1; then exit 1; fi
grep -q '不支持管道启动程序' "$WORK/pipeline"
echo 'PASS: same-line guard bodies are inspected, while unsupported startup pipelines fail instead of being executed as separate steps'

cat > "$game/run.sh" <<'RUN'
#!/bin/bash
cd "$TLBB_PATH/Server"
start_game() {
    ./Server_fix
}
start_game
RUN
run_load "$game/run.sh" "$game"
if run_validate "$game" "$billing" 0 > "$WORK/function" 2>&1; then exit 1; fi
grep -q '不支持函数式启动脚本' "$WORK/function"
echo 'PASS: function definitions cannot be silently flattened into supposedly validated startup steps'
echo 'All run-env / step checks passed.'
