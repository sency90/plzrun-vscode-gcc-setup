# ============================================================================
#  Shift+Esc = Esc (setup.sh, uninstall.sh 가 source 한다)
#  VSCode 는 단축키를 프로젝트(.vscode/) 단위로 두지 못한다. 단축키는 사용자
#  keybindings.json 하나에서만 읽는다(VSCode 1.143.1 소스: 현재 프로필의
#  keybindingsResource 만 읽음). 그래서 사용자 keybindings.json 에 표시로 묶은
#  칸을 하나 넣고, 칸 안 단축키마다 "Esc 의 원래 조건 && 파일이 그 폴더 안" 조건을 단다.
#    - 칸은 배열 맨 앞에 넣는다. 사용자가 직접 넣은 Shift+Esc 항목(뒤쪽)이 있으면 그쪽이 이긴다.
#    - 칸 밖의 글자는 한 글자도 바꾸지 않는다. 칸을 빼면 원래 파일과 바이트까지 같다.
#    - 폴더 목록은 칸 안 주석(// vsc-folder: ...)에 적는다. 같은 폴더를 다시 넣어도 하나.
#  bash 3.2 와 macOS awk 에서 돈다(python 필요 없음).
# ============================================================================

KB_BEGIN="// >>> vsc shift+escape"
KB_END="// <<< vsc shift+escape"

# kb_path : 사용자 keybindings.json 경로. 못 정하면 빈 값과 함께 KB_WHY 에 이유
kb_path() {
    KB_WHY=""
    if [ -n "${VSC_KEYBINDINGS:-}" ]; then printf '%s' "$VSC_KEYBINDINGS"; return 0; fi
    case "$(uname -s)" in
        Darwin) printf '%s' "$HOME/Library/Application Support/Code/User/keybindings.json" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                KB_WHY="WSL: VSCode keeps its keybindings on the Windows side"
                return 0
            fi
            printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json" ;;
        *) KB_WHY="unsupported system $(uname -s)" ;;
    esac
}

# kb_update FILE TSV MODE FOLDER
#   MODE add    : FOLDER 를 칸에 넣는다(칸이 없으면 만든다)
#        remove : FOLDER 를 칸에서 뺀다(마지막 폴더면 칸을 통째로 뺀다)
#        clear  : 칸을 통째로 뺀다
#        list   : 칸의 폴더 목록만 출력(파일은 그대로)
#   KB_STATUS 에 결과: added unchanged removed absent cleared refused
#   KB_WHY 에 refused 이유, KB_FOLDERS 에 바뀐 뒤 폴더 목록(줄마다 하나)
kb_update() {
    local file="$1" tsv="$2" mode="$3" folder="${4:-}" tmp st src nl=1
    KB_STATUS=""; KB_WHY=""; KB_FOLDERS=""
    if [ ! -f "$file" ]; then
        case "$mode" in
            add) mkdir -p "$(dirname "$file")" || { KB_STATUS=refused; KB_WHY="cannot make $(dirname "$file")"; return 0; } ;;
            *)   KB_STATUS=absent; return 0 ;;
        esac
        src=/dev/null; tmp="$file.vsc-new"
    else
        [ -s "$file" ] && [ "$(tail -c 1 "$file" | od -An -c | tr -d ' ')" != '\n' ] && nl=0
        src="$file"; tmp="$file.vsc-new"
    fi
    st="$file.vsc-status"
    awk -v tsv="$tsv" -v mode="$mode" -v folder="$folder" -v st="$st" \
        -v BEGIN_MARK="$KB_BEGIN" -v END_MARK="$KB_END" '
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function resc(s,   out, i, c) {        # 정규식 글자 앞에 \ (when 안의 /.../ 용)
        out = ""
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (index("\\^$.|?*+()[]{}/", c)) out = out "\\"
            out = out c
        }
        return out
    }
    function finish(status, why) { print status > st; if (why != "") print why > st }
    { L[++n] = $0 }
    END {
        # 1. 옛 칸 찾기
        b = 0; e = 0
        for (i = 1; i <= n; i++) {
            if (b == 0 && index(L[i], BEGIN_MARK)) b = i
            else if (b && index(L[i], END_MARK)) { e = i; break }
        }
        if (b && !e) { finish("refused", "the vsc part has a begin line but no end line"); exit }
        nf = 0; split_ = 0
        if (b) {
            if (index(L[b], "[split]")) split_ = 1
            for (i = b; i <= e; i++) if (match(L[i], /\/\/ vsc-folder: /)) F[++nf] = substr(L[i], RSTART + RLENGTH)
        }
        if (mode == "list") { print "list" > st; for (i = 1; i <= nf; i++) print F[i] > st; exit }
        # 2. 옛 칸 뺀 줄들 M
        m = 0
        for (i = 1; i <= n; i++) {
            if (b && i >= b && i <= e) continue
            if (b && split_ && i == e + 1 && m > 0) { M[m] = M[m] L[i]; continue }
            M[++m] = L[i]
        }
        # 3. 새 폴더 목록
        had = 0; for (i = 1; i <= nf; i++) if (F[i] == folder) had = 1
        k = 0
        if (mode == "add") { for (i = 1; i <= nf; i++) G[++k] = F[i]; if (!had) G[++k] = folder }
        else if (mode == "remove") { for (i = 1; i <= nf; i++) if (F[i] != folder) G[++k] = F[i] }
        if (mode == "add") status = had ? "unchanged" : "added"
        else if (mode == "remove") status = had ? "removed" : "absent"
        else status = b ? "cleared" : "absent"
        if (k == 0) { for (i = 1; i <= m; i++) print M[i]; finish(status, ""); for (i = 1; i <= k; i++) print G[i] > st; exit }
        # 4. 배열 시작 [ 와 그 뒤 첫 글자 찾기 (주석과 문자열은 건너뜀)
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
        # 5. 칸 만들기
        alt = ""; for (i = 1; i <= k; i++) alt = alt (i > 1 ? "|" : "") resc(G[i])
        cond = "resourcePath =~ /^(" alt ")\\//"
        nr = 0
        while ((getline row < tsv) > 0) {
            if (row ~ /^#/ || row == "") continue
            t = index(row, "\t"); cmd = substr(row, 1, t - 1); w = substr(row, t + 1)
            R[++nr] = "    { \"key\": \"shift+escape\", \"command\": \"" jesc(cmd) "\", \"when\": \"" jesc(w == "" ? cond : "(" w ") && " cond) "\" }"
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
        print "    // Shift+Esc works like Esc in the folders below. vsc writes this part; do not edit it."
        print "    // To take a folder out, run vsc --remove in it. uninstall.sh takes the whole part out."
        for (i = 1; i <= k; i++) print "    // vsc-folder: " G[i]
        for (i = 1; i <= nr; i++) print R[i] ((i < nr || !empty) ? "," : "")
        print "    " END_MARK
        if (sp) print post
        if (li > 0) for (i = li + 1; i <= m; i++) print M[i]
        else print "]"
        finish(status, "")
        for (i = 1; i <= k; i++) print G[i] > st
    }' "$src" > "$tmp"
    { IFS= read -r KB_STATUS; IFS= read -r KB_WHY || true; } < "$st"
    case "$KB_STATUS" in
        refused) rm -f "$tmp" "$st"; return 0 ;;
    esac
    if [ "$mode" = "list" ]; then KB_FOLDERS="$(sed -n '2,$p' "$st")"; KB_STATUS=list; KB_WHY=""; rm -f "$tmp" "$st"; return 0; fi
    KB_FOLDERS="$(sed -n '2,$p' "$st")"; KB_WHY=""
    rm -f "$st"
    # 원래 파일 끝에 줄바꿈이 없었으면 없게
    if [ "$nl" -eq 0 ]; then
        printf '%s' "$(cat "$tmp")" > "$tmp.1" && mv "$tmp.1" "$tmp"
    fi
    if [ -f "$file" ] && [ "$src" = "$file" ] && cmp -s "$file" "$tmp"; then rm -f "$tmp"; return 0; fi
    mv "$tmp" "$file"
}
