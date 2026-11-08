# ============================================================================
#  VSCode settings.json 의 vsc 칸 (install.sh, uninstall.sh, setup.sh 의 -cpp-snippets, -edit-context 가 source 한다)
#  칸은 둘이다. 각각 따로 넣고 뺀다.
#
#  cpp-snippets : "C_Cpp.suggestSnippets": false (task465)
#    중괄호를 치다 "if (condition) { /* code */ }" 가 끼어드는 것은 cpptools(ms-vscode.cpptools)의
#    언어 서버가 주는 코드 조각(스니펫)이다. 원본은 확장의 bin/cpptools 실행 파일 안에 들어 있고
#    (VSCode 내장 cpp 확장의 스니펫 파일에는 #region 둘만 있다), 설정 "C_Cpp.suggestSnippets"
#    하나로 언어 서버가 이 조각들을 제안 목록에 넣지 않는다.
#      - 같이 꺼지는 것: cpptools 의 다른 코드 조각(if, ifel, else, for, while, do, switch, class,
#        struct, union, main, try, namespace 같은 틀)
#      - 그대로인 것: 변수, 함수, 멤버, 키워드 이름 제안, 사용자 스니펫, 다른 언어
#
#  edit-context : "editor.editContext": false (task469)
#    한글을 치다 커서가 엉뚱한 곳으로 튀고 글자가 다른 자리에 한 번 더 써지는 것을 막는다.
#    지금 VSCode 편집기는 글자 입력을 브라우저의 EditContext API 로 받는다(1.144.0 기본값 true,
#    옛 이름 editor.experimentalEditContextEnabled). 한글처럼 조합해서 치는 입력(IME)에서 이 통로가
#    커서 자리와 조합 중인 글자를 어긋나게 받는 일이 있다(동혁님 맥과 WSL 노트북에서 겪음).
#    false 로 두면 예전처럼 숨은 textarea 로 받는다. WSL 노트북에서 이 설정으로 고쳐짐을 확인(2026-11-08).
#      - 바뀌는 것: 편집기가 글자 입력을 받는 통로 하나. 다른 편집 기능과 설정은 그대로
#
#  설정 파일 자리 (lib/vscpart.sh, keybindings.json 의 Shift+Esc 칸과 같은 코드)
#    맥     ~/Library/Application Support/Code/User/settings.json   (사용자 설정)
#    리눅스 ~/.config/Code/User/settings.json                      (사용자 설정)
#    WSL    ~/.vscode-server/data/Machine/settings.json             (Remote-WSL 의 원격 설정)
#      원격 설정은 사용자 설정보다 나중에 읽혀 이긴다. VSCode 는 원격 설정에서 scope 가
#      application 인 설정만 버린다(1.144.0 workbench 번들, RemoteUserConfiguration 의 scopes [2,3,4,5,6,7]).
#      C_Cpp.suggestSnippets 는 cpptools 가 WSL 쪽에서 읽고, editor.editContext 는 editor.* 라
#      scope 가 language-overridable(6) 이어서 원격 설정에서도 먹는다.
#      그래서 Windows 쪽 사용자 설정 파일은 건드리지 않는다.
#
#  한 파일에 칸이 둘이라, 바꿀 때마다 칸을 위에서부터 모두 뺀 다음 켜 둘 칸을 정한 순서(ST_PARTS)로
#  다시 넣는다. 그러면 어느 순서로 넣고 빼도 쉼표가 맞고, 한 줄짜리 { } 파일도 원래 줄로 돌아온다.
# ============================================================================

. "$(dirname "${BASH_SOURCE[0]}")/vscpart.sh"

ST_PARTS="cpp-snippets edit-context"   # 다시 넣는 순서. 뒤에 넣은 칸이 { 바로 뒤(맨 위)에 온다

# st_part PART : PART 의 표시 줄(ST_BEGIN, ST_END)과 키(ST_KEY)를 정한다. 모르는 PART 면 1
st_part() {
    ST_BEGIN="// >>> vsc $1"; ST_END="// <<< vsc $1"
    case "$1" in
        cpp-snippets) ST_KEY="C_Cpp.suggestSnippets" ;;
        edit-context) ST_KEY="editor.editContext" ;;
        *) return 1 ;;
    esac
}

# st_lines PART FILE : 칸 안에 넣을 줄을 FILE 에
st_lines() {
    st_part "$1"
    case "$1" in
        cpp-snippets) cat > "$2" <<EOF
    // C/C++ code snippets (if, for, class ...) are not suggested. vsc writes this part; do not edit it.
    // Turn them back on with: vsc -cpp-snippets on   (uninstall.sh also takes this part out)
    "$ST_KEY": false
EOF
        ;;
        edit-context) cat > "$2" <<EOF
    // Typing uses a hidden text area instead of EditContext, so Korean (IME) input does not
    // jump the cursor or type letters twice. vsc writes this part; do not edit it.
    // Turn EditContext back on with: vsc -edit-context on   (uninstall.sh also takes this part out)
    "$ST_KEY": false
EOF
        ;;
    esac
}

# st_path : 설정 파일 경로를 ST_PATH 에, WSL 이면 ST_REMOTE=1. 못 정하면 ST_PATH 는 빈 값, ST_WHY 에 이유.
#   kb_path 처럼 명령 치환 없이 부르고 ST_PATH 를 읽는다(task461).
st_path() {
    ST_PATH=""; ST_WHY=""; ST_REMOTE=0
    if [ -n "${VSC_SETTINGS:-}" ]; then ST_PATH="$VSC_SETTINGS"; return 0; fi
    local os="${VSC_TEST_UNAME:-$(uname -s)}"
    case "$os" in
        Darwin) ST_PATH="$HOME/Library/Application Support/Code/User/settings.json" ;;
        Linux)
            if grep -qi microsoft "${VSC_TEST_PROC_VERSION:-/proc/version}" 2>/dev/null; then
                ST_PATH="${VSCODE_AGENT_FOLDER:-$HOME/.vscode-server}/data/Machine/settings.json"; ST_REMOTE=1
            else
                ST_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json"
            fi ;;
        *) ST_WHY="unsupported system $os" ;;
    esac
    return 0
}

# st_has FILE PART : 칸이 있으면 ST_HAS=1. 칸이 깨졌거나 파일을 못 읽으면 ST_HAS=refused, ST_WHY 에 이유
st_has() {
    st_part "$2"
    vsc_part "$1" state "{" "$ST_BEGIN" "$ST_END" /dev/null ""
    case "$VP_STATUS" in
        on|folders) ST_HAS=1 ;;
        off)        ST_HAS=0 ;;
        *)          ST_HAS=refused; ST_WHY="$VP_WHY" ;;
    esac
}

# st_update FILE MODE PART
#   MODE off   : 그 기능을 끈다(PART 칸을 넣는다)
#        on    : VSCode 기본으로(PART 칸을 뺀다)
#        state : 지금 상태만
#   ST_STATUS 에 결과
#     off   : added updated unchanged refused
#     on    : cleared absent refused
#     state : off(칸 있음) on(칸 없음) refused
#   ST_WHY 에 refused 이유. ST_OWN=1 이면 칸 밖에 사용자가 직접 쓴 같은 키가 있다(뒤쪽이라 그쪽이 이긴다).
#   ST_KEY 는 PART 의 키.
#   거절하면 파일은 그대로다. 다른 칸은 상태를 그대로 두고 이 버전의 내용으로 다시 쓴다.
st_update() {
    local file="$1" mode="$2" part="$3" was
    ST_STATUS=""; ST_WHY=""; ST_OWN=0
    st_part "$part" || { ST_STATUS=refused; ST_WHY="unknown vsc part $part"; return 0; }
    st_has "$file" "$part"; was="$ST_HAS"
    if [ "$was" = refused ]; then ST_STATUS=refused
    elif [ "$mode" = state ]; then
        if [ "$was" -eq 1 ]; then ST_STATUS=off; else ST_STATUS=on; fi
    elif [ "$mode" = on ] && [ "$was" -eq 0 ]; then ST_STATUS=absent
    else
        ST_STATUS="$(st_rewrite "$file" "$mode" "$part")"
        case "$ST_STATUS" in refused*) ST_WHY="${ST_STATUS#refused }"; ST_STATUS=refused ;; esac
        if [ "$ST_STATUS" != refused ]; then
            case "$mode:$was:$ST_STATUS" in
                off:0:*)         ST_STATUS=added ;;
                off:1:same)      ST_STATUS=unchanged ;;
                off:1:*)         ST_STATUS=updated ;;
                on:*)            ST_STATUS=cleared ;;
            esac
        fi
    fi
    st_part "$part"
    # 칸 밖, 주석이 아닌 줄에 같은 키가 있으면 알린다
    if [ "$ST_STATUS" != refused ] && [ -f "$file" ] && awk -v K="\"$ST_KEY\"" '
        /\/\/ >>> vsc / { inp = 1 } inp { if (/\/\/ <<< vsc /) inp = 0; next }
        $0 !~ /^[ \t]*\/\// && index($0, K) { found = 1 } END { exit !found }' "$file"; then
        ST_OWN=1
    fi
    return 0
}

# st_rewrite FILE MODE PART : 사본에서 칸을 모두 뺐다가 켤 칸만 다시 넣고 원래 파일과 바꾼다.
#   글로 결과를 낸다: same(바이트가 같아 그대로 둠) changed, refused <이유>
#   (서브셸에서 돌아 부르는 쪽의 변수는 건드리지 않는다)
st_rewrite() (
    file="$1"; mode="$2"; part="$3"
    work="$file.vsc-work"; lines="$(mktemp "${TMPDIR:-/tmp}/vsc-st.XXXXXX")" || { echo "refused cannot make a temporary file"; exit 0; }
    trap 'rm -f "$work" "$lines"' EXIT
    rm -f "$work"
    if [ -f "$file" ]; then cp -p "$file" "$work" || { echo "refused cannot copy $file"; exit 0; }; fi
    want=""; order=""
    for p in $ST_PARTS; do
        st_has "$work" "$p"
        [ "$ST_HAS" = refused ] && { echo "refused $ST_WHY"; exit 0; }
        if [ "$p" = "$part" ]; then [ "$mode" = off ] && want="$want $p"
        elif [ "$ST_HAS" -eq 1 ]; then want="$want $p"; fi
        if [ "$ST_HAS" -eq 1 ]; then
            pos="$(grep -n -F "$ST_BEGIN" "$work" | head -1 | cut -d: -f1)"
            order="$order$pos $p
"
        fi
    done
    # 위에 있는 칸부터 뺀다. 맨 위 칸은 늘 { 바로 뒤라, 한 줄을 갈라 넣은 칸([split])도 제자리로 붙는다
    for p in $(printf '%s' "$order" | sort -n | cut -d' ' -f2); do
        st_part "$p"
        vsc_part "$work" off "{" "$ST_BEGIN" "$ST_END" /dev/null ""
        [ "$VP_STATUS" = refused ] && { echo "refused $VP_WHY"; exit 0; }
    done
    for p in $ST_PARTS; do
        case " $want " in *" $p "*) ;; *) continue ;; esac
        st_lines "$p" "$lines"
        vsc_part "$work" on "{" "$ST_BEGIN" "$ST_END" "$lines" "settings.json does not start with a JSON object {"
        [ "$VP_STATUS" = refused ] && { echo "refused $VP_WHY"; exit 0; }
    done
    if [ -f "$file" ] && cmp -s "$file" "$work"; then echo same; exit 0; fi
    mv "$work" "$file" || { echo "refused cannot write $file"; exit 0; }
    echo changed
)
