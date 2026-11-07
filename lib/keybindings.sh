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

KB_BEGIN="// >>> vsc shift+escape"
KB_END="// <<< vsc shift+escape"

# kb_path : 사용자 keybindings.json 경로. 못 정하면 빈 값과 함께 KB_WHY 에 이유
kb_path() {
    KB_WHY=""
    if [ -n "${VSC_KEYBINDINGS:-}" ]; then printf '%s' "$VSC_KEYBINDINGS"; return 0; fi
    # 시험(test/kb_platform.sh)만 VSC_TEST_UNAME, VSC_TEST_PROC_VERSION 으로 운영체제와 /proc/version 을 바꿔 끼운다(맥에서 WSL 흉내)
    case "${VSC_TEST_UNAME:-$(uname -s)}" in
        Darwin) printf '%s' "$HOME/Library/Application Support/Code/User/keybindings.json" ;;
        Linux)
            if grep -qi microsoft "${VSC_TEST_PROC_VERSION:-/proc/version}" 2>/dev/null; then
                KB_WHY="WSL: VSCode keeps its keybindings on the Windows side"
                return 0
            fi
            printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json" ;;
        *) KB_WHY="unsupported system ${VSC_TEST_UNAME:-$(uname -s)}" ;;
    esac
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
kb_update() {
    local file="$1" tsv="$2" mode="$3" tmp st src nl=1
    KB_STATUS=""; KB_WHY=""; KB_FOLDERS=""
    if [ ! -f "$file" ]; then
        case "$mode" in
            on) mkdir -p "$(dirname "$file")" || { KB_STATUS=refused; KB_WHY="cannot make $(dirname "$file")"; return 0; } ;;
            off)   KB_STATUS=absent; return 0 ;;
            *)     KB_STATUS=off; return 0 ;;
        esac
        src=/dev/null; tmp="$file.vsc-new"
    else
        [ -s "$file" ] && [ "$(tail -c 1 "$file" | od -An -c | tr -d ' ')" != '\n' ] && nl=0
        src="$file"; tmp="$file.vsc-new"
    fi
    st="$file.vsc-status"
    awk -v tsv="$tsv" -v mode="$mode" -v st="$st" \
        -v BEGIN_MARK="$KB_BEGIN" -v END_MARK="$KB_END" '
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function finish(status, why,   i) {
        print status > st; print why > st
        for (i = 1; i <= nf; i++) print F[i] > st
    }
    { L[++n] = $0 }
    END {
        # 1. 옛 칸 찾기 (v1.3.0 칸이면 폴더 목록도)
        b = 0; e = 0; nf = 0
        for (i = 1; i <= n; i++) {
            if (b == 0 && index(L[i], BEGIN_MARK)) b = i
            else if (b && index(L[i], END_MARK)) { e = i; break }
        }
        if (b && !e) { finish("refused", "the vsc part has a begin line but no end line"); exit }
        split_ = 0
        if (b) {
            if (index(L[b], "[split]")) split_ = 1
            for (i = b; i <= e; i++) if (match(L[i], /\/\/ vsc-folder: /)) F[++nf] = substr(L[i], RSTART + RLENGTH)
        }
        if (mode == "state") { finish(b ? (nf ? "folders" : "on") : "off", ""); exit }
        # 2. 옛 칸 뺀 줄들 M
        m = 0
        for (i = 1; i <= n; i++) {
            if (b && i >= b && i <= e) continue
            if (b && split_ && i == e + 1 && m > 0) { M[m] = M[m] L[i]; continue }
            M[++m] = L[i]
        }
        if (mode == "off") { for (i = 1; i <= m; i++) print M[i]; finish(b ? "cleared" : "absent", ""); exit }
        # 3. 배열 시작 [ 와 그 뒤 첫 글자 찾기 (주석과 문자열은 건너뜀)
        inb = 0; ins = 0; esc = 0; li = 0; ci = 0; nxt = ""; first = ""
        for (i = 1; i <= m && nxt == ""; i++) {
            s = M[i]; ln = length(s)
            for (j = 1; j <= ln; j++) {
                c = substr(s, j, 1)
                if (inb) { if (c == "*" && substr(s, j + 1, 1) == "/") { inb = 0; j++ } continue }
                if (ins) { if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") ins = 0; continue }
                if (c == "/" && substr(s, j + 1, 1) == "/") break
                if (c == "/" && substr(s, j + 1, 1) == "*") { inb = 1; j++; continue }
                if (c ~ /[ \t\r]/) continue
                if (first == "") {
                    first = c
                    if (c != "[") break
                    li = i; ci = j; continue
                }
                nxt = c; break
            }
            if (first != "" && first != "[") break
        }
        if (first != "" && first != "[") { finish("refused", "keybindings.json does not start with a JSON array ["); exit }
        # 4. 칸 만들기: Esc 단축키마다 같은 명령, 같은 조건의 Shift+Esc (폴더 조건 없음)
        nr = 0
        while ((getline row < tsv) > 0) {
            if (row ~ /^#/ || row == "") continue
            t = index(row, "\t"); cmd = substr(row, 1, t - 1); w = substr(row, t + 1)
            R[++nr] = "    { \"key\": \"shift+escape\", \"command\": \"" jesc(cmd) "\"" (w == "" ? "" : ", \"when\": \"" jesc(w) "\"") " }"
        }
        close(tsv)
        if (nr == 0) { finish("refused", "no Escape keybindings in " tsv); exit }
        empty = (first == "" || nxt == "]")
        if (first == "") { for (i = 1; i <= m; i++) print M[i]; print "["; li = -1 }
        else for (i = 1; i < li; i++) print M[i]
        pre = (li > 0) ? substr(M[li], 1, ci) : ""; post = (li > 0) ? substr(M[li], ci + 1) : ""
        sp = (li > 0 && post !~ /^[ \t\r]*$/) ? 1 : 0
        if (li > 0) print (sp ? pre : M[li])
        print "    " BEGIN_MARK " (plzrun-vscode-gcc-setup)" (sp ? " [split]" : "")
        print "    // Shift+Esc works like Esc everywhere in VSCode. vsc writes this part; do not edit it."
        print "    // Turn it off with: vsc -shift-esc off   (uninstall.sh also takes it out)"
        for (i = 1; i <= nr; i++) print R[i] ((i < nr || !empty) ? "," : "")
        print "    " END_MARK
        if (sp) print post
        if (li > 0) for (i = li + 1; i <= m; i++) print M[i]
        else print "]"
        finish(b ? "replaced" : "added", "")
    }' "$src" > "$tmp"
    { IFS= read -r KB_STATUS; IFS= read -r KB_WHY || true; } < "$st"
    KB_FOLDERS="$(sed -n '3,$p' "$st")"
    rm -f "$st"
    case "$KB_STATUS" in
        refused|on|folders|off) rm -f "$tmp"; return 0 ;;
    esac
    KB_WHY=""
    # 원래 파일 끝에 줄바꿈이 없었으면 없게
    if [ "$nl" -eq 0 ]; then
        printf '%s' "$(cat "$tmp")" > "$tmp.1" && mv "$tmp.1" "$tmp"
    fi
    if [ -f "$file" ] && [ "$src" = "$file" ] && cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
        [ "$KB_STATUS" = replaced ] && KB_STATUS=unchanged
        return 0
    fi
    [ "$KB_STATUS" = replaced ] && KB_STATUS=updated
    mv "$tmp" "$file"
}
