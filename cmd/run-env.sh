#!/usr/bin/env bash
# Shared, non-executing run.sh inspection for setini, step and runtop.

declare -a RUN_NAMES=() RUN_ROLES=() RUN_EXES=() RUN_CWDS=() RUN_LINES=()
declare -a RUN_ARGC=() RUN_ENVC=() RUN_UNSETC=() RUN_LIMIT_N=() RUN_LIMIT_C=()
declare -a RUN_MONITORS=() RUN_ERRORS=() RUN_CD_PATHS=() RUN_CD_LINES=()
declare -A RUN_ARGS=() RUN_ENV_NAMES=() RUN_ENV_VALUES=() RUN_UNSETS=()
declare -A RUN_VARS=() RUN_EXPORTS=() RUN_GLOBAL_UNSETS=() RUN_KEYS=()

run_native_paths() {
    TLBB_HOME="${TLBB_HOME:-/tlgame}"
    TLBB_HOME="${TLBB_HOME%/}"
    TLBB_PATH="${TLBB_PATH:-/tlgame/tlbb}"
    TLBB_PATH="${TLBB_PATH%/}"
    if [ "$TLBB_HOME" != /tlgame ] || [[ "$TLBB_PATH" != /tlgame/* ]]; then
        printf '原生环境运行根目录必须是 /tlgame，当前 TLBB_HOME=%s TLBB_PATH=%s。\n' "$TLBB_HOME" "$TLBB_PATH" >&2
        echo '请修复 /root/.gs/.env: TLBB_HOME=/tlgame, TLBB_PATH=/tlgame/tlbb，再执行 untar/setini。' >&2
        return 1
    fi
    case "$(readlink -m -- "$TLBB_PATH")" in
        /tlgame/billing|/tlgame/billing/*|/tlgame/backup|/tlgame/backup/*|/tlgame/www|/tlgame/www/*)
            echo '游戏路径不能覆盖 Billing、备份或网站目录。' >&2; return 1;;
        "$(readlink -m -- /tlgame)"/*) ;;
        *) echo 'TLBB_PATH 解析后不在 /tlgame 下，请修复配置或符号链接。' >&2; return 1;;
    esac
}

run_tokens() {
    awk '
    function word() {
        if (active) print "W\t" value
        value = ""; active = 0
    }
    function finish() { word(); print "E\t" NR }
    {
        sub(/\r$/, "")
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (escape) {
                if (c == "$") value = value "\034"
                else if (quote == "\"" && c !~ /["\\`]/) value = value "\\" c
                else value = value c
                active = 1; escape = 0; continue
            }
            if (quote == "\047") {
                if (c == "\047") quote = ""
                else if (c == "$") value = value "\034"
                else value = value c
                continue
            }
            if (c == "\\") { escape = 1; continue }
            if (quote == "\"") {
                if (c == "\"") quote = ""
                else value = value c
                continue
            }
            if (c == "\"" || c == "\047") { quote = c; active = 1; continue }
            if (c == "#" && !active) break
            if (c ~ /[ \t]/) { word(); continue }
            if (c == "<" && substr($0, i + 1, 1) == "<") {
                bad = 1; print "X\there-document"; exit 1
            }
            if (c == ">" || c == "<" || (c == "&" && substr($0, i + 1, 1) == ">")) {
                if (active && value ~ /^[0-9]+$/) { value = ""; active = 0 }
                word(); print "R\t"
                if (c == "&" || substr($0, i + 1, 1) == c) i++
                if (substr($0, i + 1, 1) == "&" || substr($0, i + 1, 1) == "|") i++
                continue
            }
            if (c == ";" || c == "&" || c == "|") {
                finish()
                if (substr($0, i + 1, 1) == c) i++
                else if (c == "|") print "P\t" NR
                continue
            }
            if (c == "(" || c == ")") { finish(); print c "\t" NR; continue }
            value = value c; active = 1
        }
        if (escape) { escape = 0; next }
        if (quote != "") { bad = 1; print "X\tmultiline quote"; exit 1 }
        finish()
    }
    END { if (!bad) { if (active) finish(); print "Z\t" } }
    ' "$1"
}

run_error() {
    RUN_ERRORS+=("第 ${RUN_LINE:-?} 行: $*")
}

run_expand() {
    local value="$1" prefix name suffix result="" pattern
    [[ "$value" != *'`'* && "$value" != *'$('* ]] || return 1
    pattern='^([^$]*)\$(\{[a-zA-Z_][a-zA-Z_0-9]*\}|[a-zA-Z_][a-zA-Z_0-9]*)(.*)$'
    while [[ "$value" == *'$'* ]]; do
        [[ "$value" =~ $pattern ]] || return 1
        prefix="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}" suffix="${BASH_REMATCH[3]}"
        name="${name#\{}"; name="${name%\}}"
        [[ ${RUN_VARS[$name]+present} ]] || return 1
        result+="$prefix${RUN_VARS[$name]}"; value="$suffix"
    done
    RUN_EXPANDED="$result$value"
    RUN_EXPANDED="${RUN_EXPANDED//$'\034'/'$'}"
    [[ "$RUN_EXPANDED" != *[[:cntrl:]]* ]]
}

run_path() {
    run_expand "$1" || return 1
    case "$RUN_EXPANDED" in
        /*) ;;
        *) [ -n "$RUN_CWD" ] || return 1
           RUN_EXPANDED="$RUN_CWD/$RUN_EXPANDED";;
    esac
    RUN_RESOLVED=$(readlink -m -- "$RUN_EXPANDED")
}

run_role() {
    case "${1,,}" in
        billing*) RUN_ROLE=Billing;;
        shm|shm_*|sharememory*) RUN_ROLE=ShareMemory;;
        login*) RUN_ROLE=Login;;
        world*) RUN_ROLE=World;;
        server*) RUN_ROLE=Server;;
        *) RUN_ROLE=Other;;
    esac
}

run_command() {
    local words=("$@") argv=() i=0 n name arg variable value executable path role key index j envc=0 unsetc=0
    local -A inline=()
    [ "${#words[@]}" -gt 0 ] || return 0
    case "${words[0]}" in
        then|else) run_command "${words[@]:1}"; return 0;;
        if|elif|fi|exit|return) return 0;;
        for|while|until|do|done|case|esac|function|source|.)
            run_error "不支持循环、函数或嵌套启动脚本，请改成明确的启动命令"; return 0;;
        unset)
            for variable in "${words[@]:1}"; do
                [[ "$variable" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] || continue
                unset 'RUN_VARS[$variable]' 'RUN_EXPORTS[$variable]'
                RUN_GLOBAL_UNSETS["$variable"]=1
            done
            return 0;;
        export)
            for arg in "${words[@]:1}"; do
                if [[ "$arg" =~ ^([a-zA-Z_][a-zA-Z_0-9]*)=(.*)$ ]]; then
                    variable="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
                    if run_expand "$value"; then
                        RUN_VARS["$variable"]="$RUN_EXPANDED"
                        RUN_EXPORTS["$variable"]="$RUN_EXPANDED"
                        unset 'RUN_GLOBAL_UNSETS[$variable]'
                    else
                        # Keep unused library exports from hiding all startup items,
                        # but never launch a step with an unresolved environment.
                        unset 'RUN_VARS[$variable]'
                        RUN_EXPORTS["$variable"]=$'\035'
                    fi
                elif [[ "$arg" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]]; then
                    RUN_EXPORTS["$arg"]="${RUN_VARS[$arg]-$'\035'}"
                    unset 'RUN_GLOBAL_UNSETS[$arg]'
                fi
            done
            return 0;;
        ulimit)
            case "${words[1]:-}:${words[2]:-}" in
                -n:unlimited|-n:[0-9]*) RUN_CURRENT_N="${words[2]}";;
                -c:unlimited|-c:[0-9]*) RUN_CURRENT_C="${words[2]}";;
            esac
            return 0;;
    esac
    while [ "$i" -lt "${#words[@]}" ] && [[ "${words[i]}" =~ ^([a-zA-Z_][a-zA-Z_0-9]*)=(.*)$ ]]; do
        variable="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
        if run_expand "$value"; then inline["$variable"]="$RUN_EXPANDED"
        else inline["$variable"]=$'\035'; fi
        i=$((i + 1))
    done
    if [ "$i" = "${#words[@]}" ]; then
        for variable in "${!inline[@]}"; do RUN_VARS["$variable"]="${inline[$variable]}"; done
        return 0
    fi
    if [ "${words[i]}" = cd ]; then
        i=$((i + 1))
        while [[ "${words[i]:-}" == -* && "${words[i]:-}" != "-" ]]; do i=$((i + 1)); done
        if [ -n "${words[i]:-}" ] && run_path "${words[i]}"; then
            RUN_CWD="$RUN_RESOLVED"; RUN_VARS[PWD]="$RUN_CWD"
            RUN_CD_PATHS+=("$RUN_CWD"); RUN_CD_LINES+=("$RUN_LINE")
        else
            RUN_CWD=""; run_error "无法静态解析 cd 路径"
        fi
        return 0
    fi
    # The tokenizer removes redirections for foreground debugging.
    for ((j=i; j<${#words[@]}; j++)); do
        if run_expand "${words[j]}"; then argv+=("$RUN_EXPANDED")
        else argv+=($'\035'); fi
    done
    # A leading exec is a shell builtin, not an external wrapper.
    [ "${argv[0]:-}" != exec ] || argv=("${argv[@]:1}")
    i=0
    while [ "$i" -lt "${#argv[@]}" ]; do
        name="${argv[i]##*/}"
        case "$name" in
            setarch)
                i=$((i + 1))
                case "${argv[i]:-}" in x86_64|i[3-6]86|linux32|linux64|aarch64|arm*|ppc*|s390*) i=$((i + 1));; esac
                while [[ "${argv[i]:-}" == -* ]]; do i=$((i + 1)); done;;
            nohup|env|setsid|nice|bash|sh|linux32|linux64)
                i=$((i + 1))
                while [ "$i" -lt "${#argv[@]}" ]; do
                    case "${argv[i]}" in
                        -c) run_error "不解析 shell -c 动态启动命令"; return 0;;
                        -n|-u|--unset|--adjustment) i=$((i + 2));;
                        -*|[a-zA-Z_]*=*) i=$((i + 1));;
                        *) break;;
                    esac
                done;;
            *) break;;
        esac
    done
    executable="${argv[i]:-}"
    [[ "$executable" != *$'\035'* ]] || {
        run_error "程序路径含未解析变量或命令替换"; return 0;
    }
    [[ "$executable" == */* ]] || return 0
    case "$executable" in *.tar|*.gz|*.zip) return 0;; esac
    [[ "$executable" != *$'\035'* ]] && run_path "$executable" || {
        run_error "无法解析程序路径"; return 0;
    }
    path="$RUN_RESOLVED"; name="${executable##*/}"
    run_role "$name"; role="$RUN_ROLE"
    case "$role:${argv[i+1]:-}" in
        ShareMemory:clear|ShareMemory:stop|ShareMemory:status|Billing:stop|Billing:status) return 0;;
    esac
    for arg in "${argv[@]}"; do
        [[ "$arg" != *$'\035'* ]] || { run_error "启动参数含未解析变量或命令替换"; return 0; }
    done
    # Absolute executable paths make step independent of the caller directory.
    argv[i]="$path"
    printf -v key '%q ' "$RUN_CWD" "${argv[@]}"
    [ "$role" != Billing ] || { RUN_BILLING_SEEN=$((RUN_BILLING_SEEN + 1)); key="Billing:$path"; }
    [ -z "${RUN_KEYS[$key]+present}" ] || return 0
    index="${#RUN_NAMES[@]}"; RUN_KEYS["$key"]="$index"
    RUN_NAMES+=("$name"); RUN_ROLES+=("$role"); RUN_EXES+=("$path")
    RUN_CWDS+=("$RUN_CWD"); RUN_LINES+=("$RUN_LINE")
    RUN_ARGC+=("${#argv[@]}")
    for j in "${!argv[@]}"; do RUN_ARGS["$index,$j"]="${argv[j]}"; done
    for variable in "${!RUN_EXPORTS[@]}"; do
        RUN_ENV_NAMES["$index,$envc"]="$variable"
        RUN_ENV_VALUES["$index,$envc"]="${RUN_EXPORTS[$variable]}"
        envc=$((envc + 1))
    done
    for variable in "${!inline[@]}"; do
        RUN_ENV_NAMES["$index,$envc"]="$variable"
        RUN_ENV_VALUES["$index,$envc"]="${inline[$variable]}"
        envc=$((envc + 1))
    done
    for variable in "${!RUN_GLOBAL_UNSETS[@]}"; do
        RUN_UNSETS["$index,$unsetc"]="$variable"; unsetc=$((unsetc + 1))
    done
    RUN_ENVC+=("$envc"); RUN_UNSETC+=("$unsetc")
    RUN_LIMIT_N+=("$RUN_CURRENT_N"); RUN_LIMIT_C+=("$RUN_CURRENT_C")
    if [ "${name,,}" = shm ]; then
        RUN_MONITORS+=("$(readlink -m -- "${path%/*}/ShareMemory")")
    else
        RUN_MONITORS+=("$path")
    fi
}

run_load() {
    local file="$1" root="$2" kind value complete=0 words=() last_words=() depth=0 skip_redirect=0 guard=0
    local key count j variable
    local -A saved=() counts=()
    root=$(readlink -m -- "$root") || return 1
    RUN_NAMES=(); RUN_ROLES=(); RUN_EXES=(); RUN_CWDS=(); RUN_LINES=()
    RUN_ARGC=(); RUN_ARGS=(); RUN_ENVC=(); RUN_ENV_NAMES=(); RUN_ENV_VALUES=()
    RUN_UNSETC=(); RUN_UNSETS=(); RUN_LIMIT_N=(); RUN_LIMIT_C=(); RUN_MONITORS=()
    RUN_ERRORS=(); RUN_KEYS=(); RUN_VARS=(); RUN_EXPORTS=(); RUN_GLOBAL_UNSETS=()
    RUN_CD_PATHS=(); RUN_CD_LINES=()
    RUN_BILLING_SEEN=0; RUN_LINE=1; RUN_CWD="$root"; RUN_CURRENT_N=""; RUN_CURRENT_C=""
    RUN_VARS[TLBB_PATH]="$root"; RUN_VARS[TLBB_HOME]="${TLBB_HOME:-${root%/*}}"
    RUN_VARS[HOME]="${HOME:-/root}"; RUN_VARS[PWD]="$root"
    RUN_VARS[LD_LIBRARY_PATH]="${LD_LIBRARY_PATH:-}"
    [ -f "$file" ] && [ ! -L "$file" ] && [ -r "$file" ] || {
        printf '无法读取普通启动脚本: %s，请修复 run.sh 后重试。\n' "$file" >&2; return 1;
    }
    bash -n <(sed 's/\r$//' "$file") || { echo 'run.sh 的 Bash 语法检查失败，请先修复脚本。' >&2; return 1; }
    while IFS=$'\t' read -r kind value; do
        case "$kind" in
            R) skip_redirect=1;;
            W)
                if [ "${#words[@]}" = 0 ]; then
                    case "$value" in if|elif) guard=1;; then|else|fi) guard=0;; esac
                fi
                if [ "$skip_redirect" = 1 ]; then skip_redirect=0; else words+=("$value"); fi;;
            E) RUN_LINE="$value"; run_command "${words[@]}"; last_words=("${words[@]}"); words=(); skip_redirect=0;;
            P) [ "$guard" = 1 ] || { RUN_LINE="$value"; run_error "不支持管道启动程序，请改成明确的单程序启动命令"; };;
            '(')
                if [ "${#last_words[@]}" = 1 ] &&
                    [[ "${last_words[0]}" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]]; then
                    run_error "不支持函数式启动脚本，请改成明确的启动命令"
                fi
                saved["$depth,cwd"]="$RUN_CWD"
                saved["$depth,n"]="$RUN_CURRENT_N"; saved["$depth,c"]="$RUN_CURRENT_C"
                count=0
                for key in "${!RUN_VARS[@]}"; do
                    saved["$depth,var,$count"]="$key"
                    saved["$depth,value,$count"]="${RUN_VARS[$key]}"; count=$((count + 1))
                done
                counts["$depth,var"]="$count"; count=0
                for key in "${!RUN_EXPORTS[@]}"; do
                    saved["$depth,export,$count"]="$key"
                    saved["$depth,env,$count"]="${RUN_EXPORTS[$key]}"; count=$((count + 1))
                done
                counts["$depth,export"]="$count"; count=0
                for key in "${!RUN_GLOBAL_UNSETS[@]}"; do
                    saved["$depth,unset,$count"]="$key"; count=$((count + 1))
                done
                counts["$depth,unset"]="$count"; depth=$((depth + 1));;
            ')')
                if [ "$depth" -gt 0 ]; then
                    depth=$((depth - 1))
                    RUN_CWD="${saved[$depth,cwd]}"
                    RUN_CURRENT_N="${saved[$depth,n]}"; RUN_CURRENT_C="${saved[$depth,c]}"
                    RUN_VARS=(); RUN_EXPORTS=(); RUN_GLOBAL_UNSETS=()
                    for ((j=0; j<counts[$depth,var]; j++)); do
                        variable="${saved[$depth,var,$j]}"
                        RUN_VARS["$variable"]="${saved[$depth,value,$j]}"
                    done
                    for ((j=0; j<counts[$depth,export]; j++)); do
                        variable="${saved[$depth,export,$j]}"
                        RUN_EXPORTS["$variable"]="${saved[$depth,env,$j]}"
                    done
                    for ((j=0; j<counts[$depth,unset]; j++)); do
                        RUN_GLOBAL_UNSETS["${saved[$depth,unset,$j]}"]=1
                    done
                fi;;
            X) printf 'run.sh 含不支持的静态解析语法: %s，请修复 run.sh。\n' "$value" >&2; return 1;;
            Z) complete=1;;
        esac
    done < <(run_tokens "$file")
    [ "$complete" = 1 ] || { echo 'run.sh 读取或解析失败。' >&2; return 1; }
}

run_validate() {
    local root="$1" billing="$2" local_billing="${3:-1}" index j path value error failed=0 games=0
    root=$(readlink -m -- "$root") && billing=$(readlink -m -- "$billing") || return 1
    for error in "${RUN_ERRORS[@]}"; do printf 'run.sh 检查失败: %s\n' "$error" >&2; failed=1; done
    for index in "${!RUN_CD_PATHS[@]}"; do
        path="${RUN_CD_PATHS[index]}"
        if [ ! -d "$path" ]; then
            printf 'run.sh 第 %s 行: cd 目录不存在: %s\n' "${RUN_CD_LINES[index]}" "$path" >&2; failed=1
        fi
    done
    for index in "${!RUN_NAMES[@]}"; do
        path="${RUN_EXES[index]}"
        [ "${RUN_ROLES[index]}" = Billing ] || games=$((games + 1))
        if [ "${RUN_ROLES[index]}" = Billing ] && [ "$local_billing" = 0 ]; then
            printf 'run.sh 第 %s 行: W机验证模式不应启动本机 Billing，请移除此启动命令。\n' "${RUN_LINES[index]}" >&2
            failed=1; continue
        fi
        case "$path" in
            "$root"/*|"$billing"/*) ;;
            *) printf 'run.sh 第 %s 行: 程序不在统一运行目录内: %s\n' "${RUN_LINES[index]}" "$path" >&2
               failed=1;;
        esac
        if [ ! -f "$path" ] || [ ! -x "$path" ]; then
            printf 'run.sh 第 %s 行: 程序不存在或不可执行: %s\n' "${RUN_LINES[index]}" "$path" >&2; failed=1
        fi
        if [ "${RUN_MONITORS[index]}" != "$path" ] &&
            { [ ! -f "${RUN_MONITORS[index]}" ] || [ ! -x "${RUN_MONITORS[index]}" ]; }; then
            printf 'run.sh 第 %s 行: shm 对应程序不存在或不可执行: %s\n' \
                "${RUN_LINES[index]}" "${RUN_MONITORS[index]}" >&2; failed=1
        fi
        for ((j=0; j<RUN_ENVC[index]; j++)); do
            value="${RUN_ENV_VALUES[$index,$j]}"
            if [[ "$value" == *$'\035'* ]]; then
                printf 'run.sh 第 %s 行: export %s 无法静态解析。\n' "${RUN_LINES[index]}" "${RUN_ENV_NAMES[$index,$j]}" >&2
                failed=1
            fi
            if [ "${RUN_ENV_NAMES[$index,$j]}" = LD_PRELOAD ]; then
                run_check_preload "$value" "${RUN_CWDS[index]}" "${RUN_LINES[index]}" || failed=1
            fi
        done
        for ((j=0; j<RUN_ARGC[index]; j++)); do
            value="${RUN_ARGS[$index,$j]}"
            case "$value" in LD_PRELOAD=*) run_check_preload "${value#*=}" "${RUN_CWDS[index]}" "${RUN_LINES[index]}" || failed=1;; esac
        done
    done
    if [ "$games" = 0 ]; then echo 'run.sh 未识别到任何游戏程序启动命令，请修复 run.sh。' >&2; failed=1; fi
    if [ "$local_billing" = 1 ] && [ "$RUN_BILLING_SEEN" = 0 ]; then
        echo 'run.sh 缺少 Billing 启动命令，请先执行 setini。' >&2; failed=1
    fi
    [ "$failed" = 0 ] || { echo "请修复 $root/run.sh 中的路径、程序或启动参数，再执行 setini；未启动任何程序。" >&2; return 1; }
}

run_check_preload() {
    local value="${1//:/ }" cwd="$2" line="$3" path
    local -a paths=()
    read -r -a paths <<< "$value"
    for path in "${paths[@]}"; do
        case "$path" in /*) ;; *) path="$cwd/$path";; esac
        [ -f "$path" ] && [ -r "$path" ] || {
            printf 'run.sh 第 %s 行: LD_PRELOAD 文件不存在或不可读: %s\n' "$line" "$path" >&2; return 1;
        }
    done
}

run_normalize() (
    local file="$1" root="$2" billing="$3" backups="$4" local_billing="${5:-1}" temp="" backup line before after
    [ -f "$file" ] && [ ! -L "$file" ] || { echo "缺少普通启动脚本 $file，请修复 run.sh。" >&2; return 1; }
    temp=$(mktemp "${file}.prepare.XXXXXX") || return 1
    trap 'rm -f -- "$temp" "$temp.billing"' EXIT
    # Replace only complete legacy path prefixes, including hook/export paths.
    # String concatenation keeps replacement paths literal, not awk replacements.
    awk -v game="$root" -v billing="$billing" '
    function rewrite(text, pattern, replacement,    result, prefix, token, suffix, before, after) {
        result = ""
        while (match(text, pattern)) {
            prefix = substr(text, 1, RSTART - 1)
            token = substr(text, RSTART, RLENGTH); suffix = substr(text, RSTART + RLENGTH)
            before = substr(prefix, length(prefix), 1); after = substr(suffix, 1, 1)
            if ((prefix == "" || before ~ /[ \t"\047=:;&|(]/) &&
                (suffix == "" || after ~ /[\/ \t"\047:;&|)>]/))
                result = result prefix replacement
            else result = result prefix token
            text = suffix
        }
        return result text
    }
    {
        sub(/\r$/, "")
        $0 = rewrite($0, "/home/billing", billing)
        $0 = rewrite($0, "/home/tlbb(/tlbb[[:alnum:]_-]*)?", game)
        print
    }' "$file" > "$temp" || return 1
    run_load "$temp" "$root" || return 1
    if [ "$local_billing" = 1 ] && [ "$RUN_BILLING_SEEN" = 0 ]; then
        printf -v line '(cd %q && ./billing up -d)' "$billing"
        # Place the managed command before any exit/conditional, in a subshell
        # so the original game working directory is unchanged.
        awk -v command="$line" '
            NR == 1 && /^#!/ { print; print command; next }
            NR == 1 { print "#!/usr/bin/env bash"; print command }
            { print }
        ' "$temp" > "$temp.billing" || return 1
        cat "$temp.billing" > "$temp" || return 1
        rm -f "$temp.billing"
        echo 'run.sh 未检测到 Billing 启动项，已补充到脚本开头 (不执行)。'
    else
        printf 'run.sh 已检测到 Billing 启动命令: %s 处，不重复追加。\n' "$RUN_BILLING_SEEN"
    fi
    bash -n "$temp" || return 1
    before=$(sha256sum "$file") && after=$(sha256sum "$temp") || return 1
    if [ "${before%% *}" != "${after%% *}" ]; then
        mkdir -p "$backups" || return 1
        backup=$(mktemp "$backups/run.sh-before-prepare-XXXXXXXX") || return 1
        cp -p -- "$file" "$backup" && chmod 600 "$backup" || return 1
        chmod --reference="$file" "$temp" && mv -fT -- "$temp" "$file" || return 1
        printf 'run.sh 已统一旧路径到 %s / %s，原脚本备份: %s\n' "$root" "$billing" "$backup"
    fi
)

run_order() {
    local role index
    RUN_ORDER=()
    for role in Billing ShareMemory Login World Server Other; do
        for index in "${!RUN_ROLES[@]}"; do
            [ "${RUN_ROLES[index]}" != "$role" ] || RUN_ORDER+=("$index")
        done
    done
}

run_describe() {
    local index="$1" j variable
    printf '目录: %s\n' "${RUN_CWDS[index]}"
    printf '角色: %s | 实际程序: %s\n' "${RUN_ROLES[index]}" "${RUN_EXES[index]}"
    printf '命令: '
    for ((j=0; j<RUN_ARGC[index]; j++)); do printf '%q ' "${RUN_ARGS[$index,$j]}"; done
    printf '\n'
    for ((j=0; j<RUN_ENVC[index]; j++)); do
        variable="${RUN_ENV_NAMES[$index,$j]}"
        case "$variable" in LD_LIBRARY_PATH|LD_PRELOAD)
            printf '  %s=%s\n' "$variable" "${RUN_ENV_VALUES[$index,$j]}";;
        esac
    done
}

run_find_pids() {
    local index="$1" proc exe path="${RUN_EXES[$1]}" monitor="${RUN_MONITORS[$1]}" arg first second cwd
    RUN_PIDS=()
    while IFS=$'\t' read -r proc exe; do
        exe="${exe% (deleted)}"
        [ -n "$exe" ] || continue
        if [ "$exe" = "$path" ] || [ "$exe" = "$monitor" ]; then
            RUN_PIDS+=("${proc##*/}"); continue
        fi
        case "${exe##*/}" in bash|sh|dash|python|python[0-9]*|perl) ;; *) continue;; esac
        first=""; second=""
        {
            IFS= read -r -d '' first && IFS= read -r -d '' second
        } 2>/dev/null < "$proc/cmdline" || continue
        [[ "$second" != -* && -n "$second" ]] || continue
        cwd=$(readlink -- "$proc/cwd") || continue
        case "$second" in /*) ;; *) second="$cwd/$second";; esac
        [ "$(readlink -m -- "$second")" != "$path" ] || RUN_PIDS+=("${proc##*/}")
    done < <(find /proc -mindepth 2 -maxdepth 2 -path '/proc/[0-9]*/exe' -printf '%h\t%l\n' 2>/dev/null)
}

run_execute() (
    local index="$1" j variable value argv=()
    cd -- "${RUN_CWDS[index]}" || return 1
    for ((j=0; j<RUN_UNSETC[index]; j++)); do unset "${RUN_UNSETS[$index,$j]}"; done
    for ((j=0; j<RUN_ENVC[index]; j++)); do
        variable="${RUN_ENV_NAMES[$index,$j]}"; value="${RUN_ENV_VALUES[$index,$j]}"
        [[ "$value" != *$'\035'* ]] || return 1
        export "$variable=$value"
    done
    [ -z "${RUN_LIMIT_N[index]}" ] || ulimit -n "${RUN_LIMIT_N[index]}" || return 1
    [ -z "${RUN_LIMIT_C[index]}" ] || ulimit -c "${RUN_LIMIT_C[index]}" || return 1
    for ((j=0; j<RUN_ARGC[index]; j++)); do argv+=("${RUN_ARGS[$index,$j]}"); done
    "${argv[@]}"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo '这是启动脚本公共组件，请使用 setini、step 或 runtop。' >&2
    exit 2
fi
