#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup (짧은 이름 vsc)
#  현재 폴더에 C/C++ 문제용 .vscode 세팅을 만들고, 같은 명령으로 설정을 바꾼다.
#    ex 방식:     main.cpp 가 있는 폴더 (sw_expert). main.cpp + 보고 있는 파일 빌드
#    single 방식: main.cpp 가 없는 폴더 (BOJ, poj). 보고 있는 파일 하나만 빌드
#  설정은 .vscode/vsc.conf 하나에 두고, tasks.json / launch.json 은 그 설정에서
#  templates/ 를 채워 다시 만든다.
#  사용법:  vsc [options] [folder]      (vsc --help)
#  출력은 전부 영어 (한글이 깨지는 터미널 대비). bash 3.2 (macOS 기본) 호환.
# ============================================================================
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

PROG="vsc"
MARK="plzrun-vscode-gcc-setup"
CONF_NAME="vsc.conf"
F5_STDIN_NAME="vsc-f5-stdin"
LANGS="c++11 c++14 c++17 c++20 c++23"
DEF_LANG="c++14"
DEF_STDIN="in"
DEF_STDOUT=""          # 빈 값 = 터미널
VALUE_OPTS="lang stdin stdout"
FLAG_OPTS="init remove ex single force help"

say()  { printf '%s: %s\n' "$PROG" "$*"; }
line() { printf '  %s\n' "$*"; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
err()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; }
hint() { printf '  %s\n' "$*" >&2; }

# --- 스크립트 실제 위치 해석 (심링크 따라감) -> templates 찾기 ---
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "${SOURCE#/}" = "$SOURCE" ] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
TPL="$SCRIPT_DIR/templates"
[ -d "$TPL" ] || { err "templates folder not found: $TPL"; exit 1; }
# Shift+Esc = Esc: 사용자 keybindings.json 의 vsc 칸 (lib/keybindings.sh)
KB_LIB="$SCRIPT_DIR/lib/keybindings.sh"
KB_TSV="$TPL/shift-esc.tsv"
[ -f "$KB_LIB" ] && . "$KB_LIB"

# ----------------------------------------------------------------------------
#  문자열 도구
# ----------------------------------------------------------------------------

# subst TEXT TOKEN VALUE : TEXT 안의 TOKEN 을 모두 VALUE 로 (bash 버전별 & \ 처리 차이 회피)
subst() {
    local t="$1" tok="$2" val="$3" out=""
    while :; do
        case "$t" in
            *"$tok"*) out="$out${t%%"$tok"*}$val"; t="${t#*"$tok"}" ;;
            *) break ;;
        esac
    done
    printf '%s' "$out$t"
}

# JSON 문자열 안에 넣을 수 있게 \ 와 " 를 이스케이프
json_esc() { subst "$(subst "$1" '\' '\\')" '"' '\"'; }

# closest WORD "CANDIDATES" : git 처럼 가장 가까운 후보를 한 줄에 하나씩 출력
#   거리 = 글자 바꾸기/넣기/빼기/이웃 두 글자 뒤바꾸기 각 1 (OSA)
#   같은 거리에 글자 구성이 같은 것(c++41 -> c++14)이 있으면 그것만, 없으면 목록 순서로 전부
#   거리가 멀면 앞부분 일치(std -> stdin, stdout)로 찾는다
closest() {
    awk -v w="$1" -v cands="$2" '
    function osa(a, b,   la, lb, i, j, c, x, y, d) {
        la = length(a); lb = length(b)
        for (i = 0; i <= la; i++) d[i, 0] = i
        for (j = 0; j <= lb; j++) d[0, j] = j
        for (i = 1; i <= la; i++) for (j = 1; j <= lb; j++) {
            c = (substr(a, i, 1) == substr(b, j, 1)) ? 0 : 1
            x = d[i-1, j] + 1; y = d[i, j-1] + 1
            if (y < x) x = y
            y = d[i-1, j-1] + c
            if (y < x) x = y
            if (i > 1 && j > 1 && substr(a, i, 1) == substr(b, j-1, 1) && substr(a, i-1, 1) == substr(b, j, 1)) {
                y = d[i-2, j-2] + 1
                if (y < x) x = y
            }
            d[i, j] = x
        }
        return d[la, lb]
    }
    function sorted(s,   n, i, j, t, a, out) {
        n = length(s)
        for (i = 1; i <= n; i++) a[i] = substr(s, i, 1)
        for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j+1] = a[j]; a[j+1] = t }
        out = ""; for (i = 1; i <= n; i++) out = out a[i]
        return out
    }
    BEGIN {
        n = split(cands, C, " "); best = 999; lw = length(w)
        if (lw == 0 || n == 0) exit
        for (i = 1; i <= n; i++) { D[i] = osa(w, C[i]); if (D[i] < best) best = D[i] }
        lim = (lw <= 3) ? 1 : 2
        if (best > lim) {
            if (lw >= 2) for (i = 1; i <= n; i++) if (index(C[i], w) == 1) print C[i]
            exit
        }
        sw = sorted(w); ana = 0
        for (i = 1; i <= n; i++) if (D[i] == best && sorted(C[i]) == sw) { print C[i]; ana = 1 }
        if (ana) exit
        for (i = 1; i <= n; i++) if (D[i] == best) print C[i]
    }'
}

# print_suggestions "a\nb" PREFIX : 추천 목록을 Did you mean 형식으로 (stderr)
print_suggestions() {
    local list="$1" pre="${2:-}" n
    [ -n "$list" ] || return 1
    n=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
    echo >&2
    if [ "$n" -eq 1 ]; then
        printf "Did you mean '%s%s'?\n" "$pre" "$list" >&2
    else
        printf 'Did you mean one of these?\n' >&2
        printf '%s\n' "$list" | while IFS= read -r s; do printf '\t%s%s\n' "$pre" "$s" >&2; done
    fi
    return 0
}

value_example() {
    case "$1" in
        lang)   hint "example: $PROG -lang c++17"
                hint "values:  $LANGS (default $DEF_LANG)" ;;
        stdin)  hint "example: $PROG -stdin in2      ($PROG -stdin default goes back to '$DEF_STDIN')" ;;
        stdout) hint "example: $PROG -stdout out2    ($PROG -stdout default goes back to the terminal)" ;;
    esac
}

usage() {
    cat <<EOF
usage: $PROG [options] [folder]

Sets up VSCode build, run and debug (.vscode/) for C++ problems,
and changes those settings later with the same command.
The old name plzrun-vscode-gcc-setup runs the same program.

Modes (picked on the first setup):
  ex       the folder has main.cpp: builds main.cpp + the file you are viewing
  single   no main.cpp: builds only the file you are viewing (BOJ style);
           the program is written next to it, named after it

Options with a value (one dash):
  -lang <std>      C++ standard: $LANGS
                   (default $DEF_LANG)
  -stdin <file>    input file, in the folder of the file you are viewing
                   (default '$DEF_STDIN')
  -stdout <file>   output file, in the same folder (default: the terminal)
  Give 'default' as the value to go back to the default.

Options without a value (two dashes):
  --init     reset every setting to the default (for a new problem)
  --remove   delete the files vsc made in .vscode/ (and its Shift+Esc keybindings)
  --ex       use ex mode
  --single   use single-file mode
  --force    replace tasks.json / launch.json even if vsc did not make them
  --help     show this help

Examples:
  $PROG                       set up this folder, or show its settings
  $PROG -lang c++17
  $PROG -stdin in2 -stdout out2
  $PROG -stdout default
  $PROG --init

Without [folder], vsc uses the nearest folder above that is already set up
(so 'vsc -stdin in2' inside poj/14216 changes the poj setup).
Shift+Esc works like Esc in VSCode for files in a folder set up by vsc
(Vim insert mode, suggestions, find, multiple cursors, and every other Esc).
VSCode reads keybindings only from your user keybindings.json, so vsc adds
a marked part there, limited to these folders; your own entries are kept.
EOF
}

# ----------------------------------------------------------------------------
#  인자 읽기
# ----------------------------------------------------------------------------
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
is_optionlike() {
    case "$1" in
        -?*|"—"*|"–"*) return 0 ;;
    esac
    return 1
}

# closest_option WORD : 가까운 옵션을 맞는 대시 개수를 붙여 출력 (-lang, --init)
closest_option() {
    closest "$1" "$VALUE_OPTS $FLAG_OPTS" | while IFS= read -r s; do
        if in_list "$s" "$VALUE_OPTS"; then echo "-$s"; else echo "--$s"; fi
    done
}

unknown_option() {
    local a="$1" name
    name="${a#-}"; name="${name#-}"
    err "unknown option '$a'"
    print_suggestions "$(closest_option "$name")" || hint "run '$PROG --help' for the list of options"
    exit 1
}

missing_value() {
    err "option '-$1' needs a value"
    value_example "$1"
    exit 1
}

OPT_LANG=""; OPT_STDIN=""; OPT_STDOUT=""
HAVE_LANG=0; HAVE_STDIN=0; HAVE_STDOUT=0
F_INIT=0; F_REMOVE=0; F_EX=0; F_SINGLE=0; F_FORCE=0; F_HELP=0
POS_DIR=""; HAVE_DIR=0
ANY_OPT=0

set_value() {  # set_value NAME VALUE
    case "$1" in
        lang)   OPT_LANG="$2";   HAVE_LANG=1 ;;
        stdin)  OPT_STDIN="$2";  HAVE_STDIN=1 ;;
        stdout) OPT_STDOUT="$2"; HAVE_STDOUT=1 ;;
    esac
    ANY_OPT=1
}

while [ $# -gt 0 ]; do
    a="$1"; shift
    # 휴대폰 자동 고침: --init 이 —init (긴 대시) 로 바뀌어 들어오는 경우
    case "$a" in
        "—"*|"–"*)
            case "$a" in "—"*) b="--${a#"—"}" ;; *) b="--${a#"–"}" ;; esac
            say "note: read '$a' as '$b' (a long dash was replaced)"
            a="$b" ;;
    esac
    case "$a" in
        -lang|-stdin|-stdout)
            name="${a#-}"
            if [ $# -eq 0 ] || is_optionlike "$1"; then missing_value "$name"; fi
            set_value "$name" "$1"; shift ;;
        -lang=*|-stdin=*|-stdout=*)
            name="${a#-}"; name="${name%%=*}"
            [ -n "${a#*=}" ] || missing_value "$name"
            set_value "$name" "${a#*=}" ;;
        --init)   F_INIT=1;   ANY_OPT=1 ;;
        --remove) F_REMOVE=1; ANY_OPT=1 ;;
        --ex)     F_EX=1;     ANY_OPT=1 ;;
        --single) F_SINGLE=1; ANY_OPT=1 ;;
        --force)  F_FORCE=1;  ANY_OPT=1 ;;
        --help|-h) F_HELP=1 ;;
        --lang|--stdin|--stdout|--lang=*|--stdin=*|--stdout=*)
            name="${a#--}"; name="${name%%=*}"
            err "unknown option '$a'"
            hint "options with a value use one dash: -$name"
            value_example "$name"
            exit 1 ;;
        -init|-remove|-ex|-single|-force|-help)
            err "unknown option '$a'"
            hint "options without a value use two dashes"
            print_suggestions "-${a}"
            exit 1 ;;
        -)  err "unknown option '-'"; hint "run '$PROG --help' for the list of options"; exit 1 ;;
        -*) unknown_option "$a" ;;
        *)
            if [ "$HAVE_DIR" -eq 1 ]; then
                err "only one folder can be given ('$POS_DIR' and '$a')"
                exit 1
            fi
            POS_DIR="$a"; HAVE_DIR=1 ;;
    esac
done

if [ "$F_HELP" -eq 1 ]; then usage; exit 0; fi

# --- 값 검사 ---
if [ "$HAVE_LANG" -eq 1 ]; then
    OPT_LANG=$(printf '%s' "$OPT_LANG" | tr 'A-Z' 'a-z')
    [ "$OPT_LANG" = "default" ] && OPT_LANG="$DEF_LANG"
    if ! in_list "$OPT_LANG" "$LANGS"; then
        err "unknown value for -lang: '$OPT_LANG'"
        value_example lang
        print_suggestions "$(closest "$OPT_LANG" "$LANGS")" || true
        exit 1
    fi
fi

check_file_value() {  # check_file_value NAME VALUE
    case "$2" in
        *'"'*|*'\'*|*'$'*|*'`'*)
            err "-$1 '$2': the file name must not contain \" \\ \$ or \`"
            exit 1 ;;
    esac
    case "$2" in
        *"
"*) err "-$1: the file name must not contain a line break"; exit 1 ;;
    esac
}
if [ "$HAVE_STDIN" -eq 1 ]; then
    [ "$OPT_STDIN" = "default" ] && OPT_STDIN="$DEF_STDIN"
    check_file_value stdin "$OPT_STDIN"
fi
if [ "$HAVE_STDOUT" -eq 1 ]; then
    [ "$OPT_STDOUT" = "default" ] && OPT_STDOUT="$DEF_STDOUT"
    check_file_value stdout "$OPT_STDOUT"
    case "$OPT_STDOUT" in
        *.cpp|*.cc|*.cxx|*.c|*.h|*.hpp)
            err "-stdout '$OPT_STDOUT' looks like a source file; it would be overwritten"
            value_example stdout
            exit 1 ;;
    esac
fi
if [ "$F_EX" -eq 1 ] && [ "$F_SINGLE" -eq 1 ]; then
    err "--ex and --single cannot be used together"
    exit 1
fi
if [ "$F_REMOVE" -eq 1 ]; then
    if [ "$HAVE_LANG$HAVE_STDIN$HAVE_STDOUT$F_INIT$F_EX$F_SINGLE$F_FORCE" != "0000000" ]; then
        err "--remove cannot be combined with other options"
        hint "run '$PROG --remove' first, then '$PROG' with the new options"
        exit 1
    fi
fi

# ----------------------------------------------------------------------------
#  대상 폴더 정하기
# ----------------------------------------------------------------------------
FOUND_ABOVE=""
if [ "$HAVE_DIR" -eq 1 ]; then
    if [ ! -d "$POS_DIR" ]; then
        err "'$POS_DIR' is not a folder"
        print_suggestions "$(closest_option "$POS_DIR")" || hint "run '$PROG --help' for the list of options"
        exit 1
    fi
    TARGET="$(cd "$POS_DIR" && pwd)"
else
    TARGET="$PWD"
    # main.cpp 나 .vscode 가 없는 곳(poj/14216 같은 문제 폴더)이면 위로 올라가 세팅된 폴더를 찾는다
    if [ ! -f "$PWD/main.cpp" ] && [ ! -d "$PWD/.vscode" ]; then
        d="$(dirname "$PWD")"
        while :; do
            if [ -f "$d/.vscode/$CONF_NAME" ]; then FOUND_ABOVE="$d"; TARGET="$d"; break; fi
            [ "$d" = "/" ] && break
            d="$(dirname "$d")"
        done
    fi
fi
VSC="$TARGET/.vscode"
CONF="$VSC/$CONF_NAME"
[ -n "$FOUND_ABOVE" ] && say "using the setup in $FOUND_ABOVE (found above this folder)"

is_ours() { grep -q "$MARK" "$1" 2>/dev/null; }

# shift_esc MODE : 이 폴더(TARGET)를 Shift+Esc 칸에 넣거나(add) 뺀다(remove). 바뀐 것만 SE_NOTE 에
SE_NOTE=""; SE_WARN=""
shift_esc() {
    local kb
    SE_NOTE=""; SE_WARN=""
    if ! command -v kb_update >/dev/null 2>&1 || [ ! -f "$KB_TSV" ]; then
        [ "$1" = add ] && SE_WARN="Shift+Esc was not set up: lib/keybindings.sh or templates/shift-esc.tsv is missing (run install.sh again)"
        return 0
    fi
    kb="$(kb_path)"
    if [ -z "$kb" ]; then
        [ "$1" = add ] && SE_WARN="Shift+Esc was not set up (${KB_WHY}); add the keybindings yourself if you need them"
        return 0
    fi
    kb_update "$kb" "$KB_TSV" "$1" "$TARGET"
    case "$KB_STATUS" in
        added)   SE_NOTE="keybindings: Shift+Esc now works like Esc in this folder (added to $kb)" ;;
        removed) SE_NOTE="keybindings: Shift+Esc is back to normal in this folder (removed from $kb)" ;;
        refused) SE_WARN="Shift+Esc was not set up: $KB_WHY ($kb was not changed)" ;;
    esac
    return 0
}

# ----------------------------------------------------------------------------
#  --remove
# ----------------------------------------------------------------------------
if [ "$F_REMOVE" -eq 1 ]; then
    removed=""; kept=""
    for f in tasks.json launch.json; do
        [ -f "$VSC/$f" ] || continue
        if is_ours "$VSC/$f"; then rm -f "$VSC/$f"; removed="$removed .vscode/$f"
        else kept="$kept .vscode/$f"; fi
    done
    for f in "$CONF_NAME" "$F5_STDIN_NAME"; do
        [ -f "$VSC/$f" ] || continue
        rm -f "$VSC/$f"; removed="$removed .vscode/$f"
    done
    if [ -n "$removed" ]; then
        say "removed from $TARGET:"
        for f in $removed; do line "$f"; done
    else
        say "nothing to remove in $TARGET (no files made by vsc)"
    fi
    for f in $kept; do line "kept $f (not made by vsc)"; done
    if [ -d "$VSC" ] && rmdir "$VSC" 2>/dev/null; then line "removed the empty .vscode/ folder"; fi
    shift_esc remove
    [ -n "$SE_NOTE" ] && line "$SE_NOTE"
    [ -n "$SE_WARN" ] && warn "$SE_WARN"
    [ -n "$removed" ] && line "run '$PROG' to set it up again"
    exit 0
fi

# ----------------------------------------------------------------------------
#  설정 읽기
# ----------------------------------------------------------------------------
FIRST=1
C_MODE=""; C_LANG="$DEF_LANG"; C_STDIN="$DEF_STDIN"; C_STDOUT="$DEF_STDOUT"
if [ -f "$CONF" ]; then
    FIRST=0
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in
            mode=*)   C_MODE="${l#mode=}" ;;
            lang=*)   C_LANG="${l#lang=}" ;;
            stdin=*)  C_STDIN="${l#stdin=}" ;;
            stdout=*) C_STDOUT="${l#stdout=}" ;;
        esac
    done < "$CONF"
    case "$C_MODE" in
        ex|single) : ;;
        *) warn ".vscode/$CONF_NAME has a bad mode '$C_MODE'; detecting it again"; C_MODE="" ;;
    esac
    if ! in_list "$C_LANG" "$LANGS"; then
        warn ".vscode/$CONF_NAME has a bad lang '$C_LANG'; using $DEF_LANG"; C_LANG="$DEF_LANG"
    fi
    [ -n "$C_STDIN" ] || C_STDIN="$DEF_STDIN"
fi
O_MODE="$C_MODE"; O_LANG="$C_LANG"; O_STDIN="$C_STDIN"; O_STDOUT="$C_STDOUT"

# --- 새 값 ---
MODE_WHY=""
if [ "$F_EX" -eq 1 ]; then N_MODE="ex"; MODE_WHY="--ex"
elif [ "$F_SINGLE" -eq 1 ]; then N_MODE="single"; MODE_WHY="--single"
elif [ -n "$C_MODE" ]; then N_MODE="$C_MODE"
elif [ -f "$TARGET/main.cpp" ]; then N_MODE="ex"; MODE_WHY="main.cpp found"
else N_MODE="single"; MODE_WHY="no main.cpp here"
fi
N_LANG="$C_LANG"; N_STDIN="$C_STDIN"; N_STDOUT="$C_STDOUT"
if [ "$F_INIT" -eq 1 ]; then N_LANG="$DEF_LANG"; N_STDIN="$DEF_STDIN"; N_STDOUT="$DEF_STDOUT"; fi
[ "$HAVE_LANG" -eq 1 ] && N_LANG="$OPT_LANG"
[ "$HAVE_STDIN" -eq 1 ] && N_STDIN="$OPT_STDIN"
[ "$HAVE_STDOUT" -eq 1 ] && N_STDOUT="$OPT_STDOUT"

if [ -n "$N_STDOUT" ] && [ "$N_STDOUT" = "$N_STDIN" ]; then
    err "stdin and stdout would be the same file ('$N_STDIN'); the input would be overwritten"
    exit 1
fi

# --- 파일 경로 식 (VSCode 변수) ---
path_expr() {  # 상대 경로는 보고 있는 파일의 폴더 기준
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s' "\${fileDirname}/$1" ;;
    esac
}
show_stdin()  { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s  (in the folder of the file you are viewing)' "$1" ;; esac; }
show_stdout() { if [ -z "$1" ]; then printf 'terminal'; else case "$1" in /*) printf '%s' "$1" ;; *) printf '%s  (in the folder of the file you are viewing)' "$1" ;; esac; fi; }
show_mode()   { if [ "$1" = "ex" ]; then printf 'ex  (main.cpp + the file you are viewing)'; else printf 'single  (only the file you are viewing)'; fi; }
short_out()   { if [ -z "$1" ]; then printf 'terminal'; else printf '%s' "$1"; fi; }

# ----------------------------------------------------------------------------
#  tasks.json / launch.json 만들기
# ----------------------------------------------------------------------------
build_files() {
    local in_e out_e exe f5in tpl t run_rel run_exam prep redir lldb
    in_e="$(path_expr "$N_STDIN")"
    f5in="\${workspaceFolder}/.vscode/$F5_STDIN_NAME"
    if [ "$N_MODE" = "ex" ]; then exe_rel="\${workspaceFolder}/pgm_release"; exe_exam="\${workspaceFolder}/pgm_exam"
    else exe_rel="\${fileDirname}/\${fileBasenameNoExtension}"; exe_exam=""; fi

    # run 명령: stdin 파일이 있으면 리다이렉트, 없으면 터미널 입력 + 경고 한 줄
    run_cmd() {  # run_cmd EXE TIMEPREFIX
        local o="" tail=""
        if [ -n "$N_STDOUT" ]; then
            out_e="$(path_expr "$N_STDOUT")"
            o=" > \"$out_e\""
            tail="; s=\$?; echo \"vsc: stdout was written to $out_e\"; exit \$s"
        fi
        printf '%s' "if [ -f \"$in_e\" ]; then $2\"$1\" < \"$in_e\"$o; else echo \"vsc warning: stdin file not found: $in_e (reading from the terminal)\" >&2; $2\"$1\"$o; fi$tail"
    }
    run_rel="$(run_cmd "$exe_rel" "")"
    [ "$N_MODE" = "ex" ] && run_exam="$(run_cmd "$exe_exam" "time ")"
    prep="if [ -f \"$in_e\" ]; then cp \"$in_e\" \"$f5in\"; echo \"vsc: F5 stdin = $in_e\"; else : > \"$f5in\"; echo \"vsc warning: stdin file not found: $in_e (F5 starts with empty input)\"; fi"

    # F5 gdb 와 Ctrl+F5 는 args 를 셸에 넘기므로 리다이렉트가 먹는다. F5 lldb 는 setupCommands 로.
    redir="\"<\", \"$f5in\""
    lldb="                    { \"description\": \"stdin\", \"text\": \"$(json_esc "settings set target.input-path \"$f5in\"")\" }"
    if [ -n "$N_STDOUT" ]; then
        out_e="$(path_expr "$N_STDOUT")"
        redir="$redir, \">\", \"$out_e\""
        lldb="$lldb,
                    { \"description\": \"stdout\", \"text\": \"$(json_esc "settings set target.output-path \"$out_e\"")\" }"
    fi

    local note_in note_out
    note_in="$(show_stdin "$N_STDIN")"
    note_out="$(show_stdout "$N_STDOUT")"

    t="$(cat "$TPL/tasks.$N_MODE.json")"
    t="$(subst "$t" "@STD@" "$N_LANG")"
    t="$(subst "$t" "@STDIN_NOTE@" "$note_in")"
    t="$(subst "$t" "@STDOUT_NOTE@" "$note_out")"
    t="$(subst "$t" "@RUN_RELEASE@" "$(json_esc "$run_rel")")"
    t="$(subst "$t" "@RUN_EXAM@" "$(json_esc "$run_exam")")"
    t="$(subst "$t" "@PREP_F5@" "$(json_esc "$prep")")"
    NEW_TASKS="$t"

    t="$(cat "$TPL/launch.json")"
    if [ "$N_MODE" = "ex" ]; then
        t="$(subst "$t" "@PROGRAM_NAME@" "pgm_debug")"
        t="$(subst "$t" "@PROGRAM@" "\${workspaceFolder}/pgm_debug")"
        t="$(subst "$t" "@CWD@" "\${workspaceFolder}")"
    else
        t="$(subst "$t" "@PROGRAM_NAME@" "\${fileBasenameNoExtension}")"
        t="$(subst "$t" "@PROGRAM@" "\${fileDirname}/\${fileBasenameNoExtension}")"
        t="$(subst "$t" "@CWD@" "\${fileDirname}")"
    fi
    t="$(subst "$t" "@STDIN_NOTE@" "$note_in")"
    t="$(subst "$t" "@STDOUT_NOTE@" "$note_out")"
    t="$(subst "$t" "@REDIRECT_ARGS@" "$redir")"
    t="$(subst "$t" "@LLDB_SETUP@" "$lldb")"
    NEW_LAUNCH="$t"

    NEW_CONF="# vsc settings (plzrun-vscode-gcc-setup). Change them with the vsc command (vsc --help).
mode=$N_MODE
lang=$N_LANG
stdin=$N_STDIN
stdout=$N_STDOUT"
}
build_files

# --- 이 도구가 만들지 않은 파일은 --force 없이 덮지 않는다 ---
FOREIGN=""
for f in tasks.json launch.json; do
    if [ -f "$VSC/$f" ] && ! is_ours "$VSC/$f"; then FOREIGN="$FOREIGN $f"; fi
done
if [ -n "$FOREIGN" ] && [ "$F_FORCE" -eq 0 ]; then
    for f in $FOREIGN; do err ".vscode/$f already exists and was not made by vsc"; done
    hint "nothing was changed."
    hint "to replace it, run the same command with --force (for example: $PROG --force)"
    exit 1
fi

# --- 쓰기: 내용이 같으면 그대로 둔다 ---
W_CREATED=""; W_REWROTE=""; W_OLDER=""; W_FOREIGN=""
write_file() {  # write_file NAME CONTENT
    local p="$VSC/$1" old
    if [ -f "$p" ]; then
        old="$(cat "$p")"
        [ "$old" = "$2" ] && return 0
        printf '%s\n' "$2" > "$p"
        if in_list "$1" "$FOREIGN"; then W_FOREIGN="$W_FOREIGN, $1"
        elif [ "$FIRST" -eq 1 ]; then W_OLDER="$W_OLDER, $1"
        else W_REWROTE="$W_REWROTE, $1"; fi
    else
        printf '%s\n' "$2" > "$p"
        W_CREATED="$W_CREATED, $1"
    fi
}
mkdir -p "$VSC"
write_file "$CONF_NAME" "$NEW_CONF"
write_file tasks.json "$NEW_TASKS"
write_file launch.json "$NEW_LAUNCH"
shift_esc add

print_file_notes() {
    [ -n "$W_CREATED" ] && line ".vscode: created ${W_CREATED#, }"
    [ -n "$W_REWROTE" ] && line ".vscode: rewrote ${W_REWROTE#, }"
    [ -n "$W_OLDER" ]   && line ".vscode: updated ${W_OLDER#, } (made by an older version of this tool)"
    [ -n "$W_FOREIGN" ] && line ".vscode: replaced ${W_FOREIGN#, } (not made by vsc; --force)"
    [ -n "$SE_NOTE" ] && line "$SE_NOTE"
    [ -n "$SE_WARN" ] && warn "$SE_WARN"
    return 0
}

# --- stdin 파일이 있는지 (직접 바꿨을 때만 경고) ---
check_stdin_exists() {
    local v="$1" found="" names
    case "$v" in
        /*) [ -f "$v" ] && found=1 ;;
        *)  if [ "$N_MODE" = "ex" ]; then [ -f "$TARGET/$v" ] && found=1
            else [ -n "$(find "$TARGET" -maxdepth 3 -path "*/$v" -type f 2>/dev/null | head -1)" ] && found=1; fi ;;
    esac
    [ -n "$found" ] && return 0
    if [ "$N_MODE" = "ex" ]; then
        warn "stdin file '$v' does not exist in $TARGET yet (setting saved; runs read from the terminal until it exists)"
    else
        warn "no file named '$v' next to your sources yet (setting saved; runs read from the terminal until it exists)"
    fi
    case "$v" in
        */*) : ;;
        *)
            names=$(find "$TARGET" -maxdepth 2 -type f ! -name '.*' ! -path '*/.vscode/*' ! -path '*.dSYM/*' \
                        ! -name '*.cpp' ! -name '*.cc' ! -name '*.c' ! -name '*.h' ! -name '*.hpp' \
                        ! -name '*.json' ! -name '*.md' ! -name '*.o' 2>/dev/null \
                    | while IFS= read -r p; do [ -x "$p" ] || basename "$p"; done | sort -u | tr '\n' ' ')
            print_suggestions "$(closest "$v" "$names")" || true ;;
    esac
}

# ----------------------------------------------------------------------------
#  결과 출력
# ----------------------------------------------------------------------------
if [ "$FIRST" -eq 1 ]; then
    say "set up $TARGET"
    line "mode:   $(show_mode "$N_MODE")  [$MODE_WHY]"
    line "lang:   $N_LANG"
    line "stdin:  $(show_stdin "$N_STDIN")"
    line "stdout: $(show_stdout "$N_STDOUT")"
    print_file_notes
    if [ "$N_MODE" = "ex" ]; then
        line "Ctrl+Shift+B: build release (-O2).  F5: debug (-g).  Tasks: build/run exam (-O0, timed)."
    else
        line "Ctrl+Shift+B: build the file you are viewing (-O2).  F5: debug it (-g)."
        line "Tasks: run release (uses stdin/stdout above)."
    fi
    [ "$N_MODE" = "ex" ] && [ ! -f "$TARGET/main.cpp" ] && warn "main.cpp not found in $TARGET (ex builds need it)"
    [ "$HAVE_STDIN" -eq 1 ] && check_stdin_exists "$N_STDIN"
    exit 0
fi

CHANGES=""
cmp_val() {  # cmp_val KEY OLD NEW OLD_SHOWN NEW_SHOWN
    [ "$2" != "$3" ] && CHANGES="$CHANGES|$(printf '%-7s %s -> %s' "$1:" "$4" "$5")"
    return 0
}
cmp_val mode   "$O_MODE"   "$N_MODE"   "$O_MODE" "$N_MODE"
cmp_val lang   "$O_LANG"   "$N_LANG"   "$O_LANG" "$N_LANG"
cmp_val stdin  "$O_STDIN"  "$N_STDIN"  "$O_STDIN" "$N_STDIN"
cmp_val stdout "$O_STDOUT" "$N_STDOUT" "$(short_out "$O_STDOUT")" "$(short_out "$N_STDOUT")"

if [ "$ANY_OPT" -eq 0 ]; then
    # 인자 없는 vsc: 현재 설정 보여 주기
    say "settings in $TARGET"
    line "mode:   $(show_mode "$N_MODE")"
    line "lang:   $N_LANG"
    line "stdin:  $(show_stdin "$N_STDIN")"
    line "stdout: $(show_stdout "$N_STDOUT")"
    print_file_notes
    line "change them with: $PROG -lang <std> | -stdin <file> | -stdout <file>   ($PROG --help)"
    exit 0
fi

if [ -n "$CHANGES" ]; then
    if [ "$F_INIT" -eq 1 ]; then say "reset $TARGET to the default settings"
    else say "updated $TARGET"; fi
    old_ifs="$IFS"; IFS='|'
    for c in $CHANGES; do [ -n "$c" ] && line "$c"; done
    IFS="$old_ifs"
else
    if [ "$F_INIT" -eq 1 ]; then say "nothing changed in $TARGET (every setting is already the default)"
    else
        # 직접 준 옵션 것만 보여 준다
        what=""
        [ "$F_EX$F_SINGLE" != "00" ] && what="$what, mode is already $N_MODE"
        [ "$HAVE_LANG" -eq 1 ] && what="$what, lang is already $N_LANG"
        [ "$HAVE_STDIN" -eq 1 ] && what="$what, stdin is already $N_STDIN"
        [ "$HAVE_STDOUT" -eq 1 ] && what="$what, stdout is already $(short_out "$N_STDOUT")"
        what="${what#, }"
        if [ -n "$what" ]; then say "nothing changed in $TARGET ($what)"
        else say "nothing changed in $TARGET"; fi
    fi
fi
print_file_notes
[ "$N_MODE" = "ex" ] && [ "$O_MODE" != "ex" ] && [ ! -f "$TARGET/main.cpp" ] && warn "main.cpp not found in $TARGET (ex builds need it)"
if [ "$HAVE_STDIN" -eq 1 ] && [ "$O_STDIN" != "$N_STDIN" ]; then check_stdin_exists "$N_STDIN"; fi
exit 0
