#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
source "$ROOT/gsenv.sh"
ENV_DIR="$WORK/environment"
unset TLBB_OFFLINE_MODE TLBB_OFFLINE_DIR
select_install_mode
[ "$GSENV_OFFLINE_MODE" = 0 ]
TLBB_OFFLINE_MODE=1 select_install_mode --online
[ "$GSENV_OFFLINE_MODE" = 0 ]
select_install_mode --offline --online
[ "$GSENV_OFFLINE_MODE" = 0 ]
select_install_mode --online --offline
[ "$GSENV_OFFLINE_MODE" = 1 ]
select_install_mode --dbpass --offline
[ "$GSENV_OFFLINE_MODE" = 0 ]
select_install_mode --offline-dir --offline
[ "$GSENV_OFFLINE_MODE" = 0 ] && [ "$GSENV_OFFLINE_DIR" = --offline ]
if select_install_mode --dbpass; then exit 1; fi
if select_install_mode --offline-dir; then exit 1; fi
if TLBB_OFFLINE_MODE=invalid select_install_mode; then exit 1; fi
echo 'PASS: default online, CLI precedence, option values, invalid arguments'

id() { echo 0; }
brand_banner() { :; }
download() { :; }
deploy() { mkdir -p "$ENV_DIR"; }
find_offline_archive() {
    printf 'checked\n' >> "$WORK/archive-checks"
    printf '%s\n' "$WORK/offline-el9.tar.gz"
}
bash() {
    if [ "${1:-}" = install.sh ]; then
        printf '%s\n' "$@" > "$WORK/forwarded"
        echo 'installer stderr probe' >&2
        return "${INSTALL_RESULT:-0}"
    fi
    command bash "$@"
}
run_bootstrap() {
    local status=0
    (gsenv_main "$@") > "$WORK/output" 2>&1 || status=$?
    [ "$status" = "${EXPECTED_STATUS:-0}" ] || { cat "$WORK/output"; exit 1; }
}

mkdir -p "$ENV_DIR/offline" "$WORK/archive/offline"
printf 'legacy\n' > "$ENV_DIR/offline/legacy-package"
printf 'component\n' > "$WORK/archive/offline/component"
tar -czf "$WORK/offline-el9.tar.gz" -C "$WORK/archive" offline
run_bootstrap
[ "$(sed -n '2p' "$WORK/forwarded")" = --online ]
[ ! -f "$WORK/archive-checks" ]
[ ! -f "$ENV_DIR/offline/component" ]
run_bootstrap --online --dbpass 'value with spaces'
grep -qx 'value with spaces' "$WORK/forwarded"
[ ! -f "$WORK/archive-checks" ]
TLBB_OFFLINE_MODE=1 run_bootstrap --online
[ ! -f "$WORK/archive-checks" ]
run_bootstrap --dbpass --offline
[ "$(sed -n '2p' "$WORK/forwarded")" = --online ]
[ ! -f "$WORK/archive-checks" ]
echo 'PASS: online ignores existing archive/directory and preserves argument boundaries'

run_bootstrap --offline --offline-dir "$WORK/custom offline"
[ "$(sed -n '2p' "$WORK/forwarded")" = --offline ]
[ -f "$WORK/custom offline/component" ]
run_bootstrap --offline --offline-dir 'relative offline'
[ -f "$ENV_DIR/relative offline/component" ]
TLBB_OFFLINE_MODE=1 TLBB_OFFLINE_DIR="$WORK/environment-offline" run_bootstrap
[ "$(sed -n '2p' "$WORK/forwarded")" = --offline ]
[ -f "$WORK/environment-offline/component" ]
printf 'corrupt archive\n' > "$WORK/offline-el9.tar.gz"
rm -f "$WORK/forwarded"
EXPECTED_STATUS=1 run_bootstrap --offline --offline-dir "$WORK/broken"
[ ! -f "$WORK/forwarded" ]
echo 'PASS: explicit offline extracts into requested directory and aborts on corrupt archive'

INSTALL_RESULT=23 EXPECTED_STATUS=23 run_bootstrap --online
grep -q 'installer stderr probe' "$ENV_DIR/install.log"
grep -q '23' "$WORK/output"
echo 'PASS: installer stderr and exit status reach bootstrap caller'

# Exercise the empty BASH_SOURCE case of the actual curl | bash entry point,
# replacing only the entry function so no package/network operations can run.
{
    sed '/^if \[ "${BASH_SOURCE\[0\]:-\$0}" = "\$0" \]; then/,$d' "$ROOT/gsenv.sh"
    printf '\ngsenv_main() { printf "piped-entry:%%s\\n" "$1"; }\n'
    printf 'if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then gsenv_main "$@"; fi\n'
} | command bash -s -- --online > "$WORK/piped"
grep -qx 'piped-entry:--online' "$WORK/piped"
echo 'PASS: piped bootstrap executes its guarded main function'
echo 'All bootstrap mode checks passed.'
