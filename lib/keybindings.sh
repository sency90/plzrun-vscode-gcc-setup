# ============================================================================
#  Shift+Esc = Esc (install.sh, uninstall.sh, setup.sh 의 -shift-esc 가 source 한다)
#  VSCode 는 단축키를 프로젝트(.vscode/) 단위로 두지 못한다. 단축키는 사용자
#  keybindings.json 하나에서만 읽는다(VSCode 1.143.1 소스: 현재 프로필의
#  keybindingsResource 만 읽음). 그래서 사용자 keybindings.json 에 표시로 묶은
#  칸을 하나 넣고, 칸 안에 Esc 단축키를 같은 조건으로 Shift+Esc 에 복사한다.
#    - PC 전체 설정이다. 폴더 조건이 없다(v1.4.0). 프로젝트 명령(vsc, --init, --remove)은
#      칸을 건드리지 않는다. 켜기는 install.sh 와 vsc -shift-esc on, 끄기는 uninstall.sh 와 vsc -shift-esc off.
#    - 칸은 배열 맨 앞에 넣는다. 사용자가 직접 넣은 Shift+Esc 항목(뒤쪽)이 있으면 그쪽이 이긴다.
#    - 칸 밖의 글자는 한 글자도 바꾸지 않는다. 칸을 빼면 원래 파일과 바이트까지 같다.
#    - v1.3.0 의 폴더 한정 칸(// vsc-folder: 줄, resourcePath 조건)도 같은 표시라 그대로 알아보고 바꾼다.
#  bash 3.2 와 macOS awk 에서 돈다(python 필요 없음).
# ============================================================================

. "$(dirname "${BASH_SOURCE[0]}")/vscpart.sh"

KB_BEGIN="// >>> vsc shift+escape"
KB_END="// <<< vsc shift+escape"

# kb_path : 사용자 keybindings.json 경로를 KB_PATH 에 둔다. 못 정하면 KB_PATH 는 빈 값, KB_WHY 에 이유.
#   부르는 쪽은 kb_path 를 그냥 부르고 KB_PATH 를 읽는다. kb="$(kb_path)" 처럼 명령 치환으로 부르지 않는다:
#   치환은 서브셸이라 거기서 정한 KB_WHY 가 부르는 쪽에 남지 않고, set -u 에서 "KB_WHY: unbound variable" 로 멈춘다
#   (task461, WSL 의 install.sh 85행. 맥은 경로가 나와 그 줄을 안 타서 task373 때 안 드러났다).
kb_path() {
    KB_PATH=""; KB_WHY=""
    if [ -n "${VSC_KEYBINDINGS:-}" ]; then KB_PATH="$VSC_KEYBINDINGS"; return 0; fi
    # 시험(test/kb_platform.sh)만 VSC_TEST_UNAME, VSC_TEST_PROC_VERSION 으로 운영체제와 /proc/version 을 바꿔 끼운다(맥에서 WSL 흉내)
    local os="${VSC_TEST_UNAME:-$(uname -s)}"
    case "$os" in
        Darwin) KB_PATH="$HOME/Library/Application Support/Code/User/keybindings.json" ;;
        Linux)
            if grep -qi microsoft "${VSC_TEST_PROC_VERSION:-/proc/version}" 2>/dev/null; then
                KB_WHY="WSL: VSCode keeps its keybindings on the Windows side"
            else
                KB_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
            fi ;;
        *) KB_WHY="unsupported system $os" ;;
    esac
    return 0
}

# kb_update FILE TSV MODE
#   MODE on    : 칸을 PC 전체용으로 넣는다(옛 칸이 있으면 새 칸으로 바꾼다)
#        off   : 칸을 통째로 뺀다
#        state : 파일은 그대로, 지금 상태만 본다
#   KB_STATUS 에 결과
#     on    : added(칸이 없었음) updated(옛 칸을 바꿈) unchanged(이미 같음) refused
#     off   : cleared absent refused
#     state : on folders(v1.3.0 폴더 한정 칸) off refused
#   KB_WHY 에 refused 이유, KB_FOLDERS 에 옛 칸의 폴더 목록(v1.3.0 칸이었을 때, 줄마다 하나)
#   칸을 넣고 빼는 일은 lib/vscpart.sh 의 vsc_part 가 한다(settings.json 의 vsc 칸과 같은 코드).
kb_update() {
    local file="$1" tsv="$2" mode="$3" lines
    KB_STATUS=""; KB_WHY=""; KB_FOLDERS=""
    lines="$(mktemp "${TMPDIR:-/tmp}/vsc-kb.XXXXXX")" || { KB_STATUS=refused; KB_WHY="cannot make a temporary file"; return 0; }
    # 칸 안에 들어갈 줄: 안내 주석 두 줄 + Esc 단축키마다 같은 명령, 같은 조건의 Shift+Esc (폴더 조건 없음)
    if [ "$mode" = on ]; then
        awk '
        function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
        BEGIN {
            print "    // Shift+Esc works like Esc everywhere in VSCode. vsc writes this part; do not edit it."
            print "    // Turn it off with: vsc -shift-esc off   (uninstall.sh also takes it out)"
        }
        /^#/ || $0 == "" { next }
        {
            t = index($0, "\t"); cmd = substr($0, 1, t - 1); w = substr($0, t + 1)
            print "    { \"key\": \"shift+escape\", \"command\": \"" jesc(cmd) "\"" (w == "" ? "" : ", \"when\": \"" jesc(w) "\"") " }"
        }' "$tsv" > "$lines"
        if ! grep -q '^    {' "$lines"; then
            rm -f "$lines"; KB_STATUS=refused; KB_WHY="no Escape keybindings in $tsv"; return 0
        fi
    fi
    vsc_part "$file" "$mode" "[" "$KB_BEGIN" "$KB_END" "$lines" "keybindings.json does not start with a JSON array ["
    rm -f "$lines"
    KB_STATUS="$VP_STATUS"; KB_WHY="$VP_WHY"; KB_FOLDERS="$VP_FOLDERS"
}
