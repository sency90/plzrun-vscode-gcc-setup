# ============================================================================
#  C/C++ 코드 조각 제안 끄기 (install.sh, uninstall.sh, setup.sh 의 -cpp-snippets 가 source 한다, task465)
#  중괄호를 치다 "if (condition) { /* code */ }" 가 끼어드는 것은 cpptools(ms-vscode.cpptools)의
#  언어 서버가 주는 코드 조각(스니펫)이다. 원본은 확장의 bin/cpptools 실행 파일 안에 들어 있고
#  (VSCode 내장 cpp 확장의 스니펫 파일에는 #region 둘만 있다), 설정 "C_Cpp.suggestSnippets"
#  하나로 언어 서버가 이 조각들을 제안 목록에 넣지 않는다.
#    - 같이 꺼지는 것: cpptools 의 다른 코드 조각(if, ifel, else, for, while, do, switch, class,
#      struct, union, main, try, namespace 같은 틀)
#    - 그대로인 것: 변수, 함수, 멤버, 키워드 이름 제안, 사용자 스니펫, 다른 언어
#  설정 파일에 vsc 칸을 넣는다(lib/vscpart.sh, keybindings.json 의 Shift+Esc 칸과 같은 코드).
#    맥     ~/Library/Application Support/Code/User/settings.json   (사용자 설정)
#    리눅스 ~/.config/Code/User/settings.json                      (사용자 설정)
#    WSL    ~/.vscode-server/data/Machine/settings.json             (Remote-WSL 의 원격 설정)
#      WSL 에서 cpptools 는 WSL 쪽에서 돈다. 원격 설정은 사용자 설정보다 나중에 읽혀 이긴다.
#      Windows 쪽 사용자 설정 파일은 건드리지 않는다(단축키와 달리 설정은 원격 자리가 있다).
# ============================================================================

. "$(dirname "${BASH_SOURCE[0]}")/vscpart.sh"

ST_BEGIN="// >>> vsc cpp-snippets"
ST_END="// <<< vsc cpp-snippets"
ST_KEY="C_Cpp.suggestSnippets"

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

# st_update FILE MODE
#   MODE off   : 코드 조각을 끈다(vsc 칸을 넣는다)
#        on    : VSCode 기본으로(vsc 칸을 뺀다)
#        state : 지금 상태만
#   ST_STATUS 에 결과
#     off   : added updated unchanged refused
#     on    : cleared absent refused
#     state : off(칸 있음) on(칸 없음) refused
#   ST_WHY 에 refused 이유. ST_OWN=1 이면 칸 밖에 사용자가 직접 쓴 "C_Cpp.suggestSnippets" 가 있다(뒤쪽이라 그쪽이 이긴다).
st_update() {
    local file="$1" mode="$2" lines
    ST_STATUS=""; ST_WHY=""; ST_OWN=0
    lines="$(mktemp "${TMPDIR:-/tmp}/vsc-st.XXXXXX")" || { ST_STATUS=refused; ST_WHY="cannot make a temporary file"; return 0; }
    cat > "$lines" <<EOF
    // C/C++ code snippets (if, for, class ...) are not suggested. vsc writes this part; do not edit it.
    // Turn them back on with: vsc -cpp-snippets on   (uninstall.sh also takes this part out)
    "$ST_KEY": false
EOF
    case "$mode" in
        off)   vsc_part "$file" on "{" "$ST_BEGIN" "$ST_END" "$lines" "settings.json does not start with a JSON object {" ;;
        on)    vsc_part "$file" off "{" "$ST_BEGIN" "$ST_END" "$lines" "" ;;
        state) vsc_part "$file" state "{" "$ST_BEGIN" "$ST_END" "$lines" ""
               case "$VP_STATUS" in on|folders) VP_STATUS=off ;; off) VP_STATUS=on ;; esac ;;
    esac
    rm -f "$lines"
    ST_STATUS="$VP_STATUS"; ST_WHY="$VP_WHY"
    # 칸 밖, 주석이 아닌 줄에 같은 키가 있으면 알린다
    if [ -f "$file" ] && awk -v B="$ST_BEGIN" -v E="$ST_END" -v K="\"$ST_KEY\"" '
        index($0, B) { inp = 1 } inp { if (index($0, E)) inp = 0; next }
        $0 !~ /^[ \t]*\/\// && index($0, K) { found = 1 } END { exit !found }' "$file"; then
        ST_OWN=1
    fi
    return 0
}
