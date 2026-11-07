# ============================================================================
#  VSCode 사용자 파일(keybindings.json, settings.json)에 vsc 칸을 넣고 빼는 공용 코드
#  (lib/keybindings.sh 와 lib/settings.sh 가 source 한다. v1.4.0 의 kb_update 에서 떼어 냄, task465)
#    - 칸은 맨 바깥 [ 또는 { 바로 뒤에 넣는다. 사용자가 뒤쪽에 같은 항목을 두면 그쪽이 이긴다.
#    - 칸 밖의 글자는 한 글자도 바꾸지 않는다. 칸을 빼면 원래 파일과 바이트까지 같다.
#    - 주석(// 와 /* */)과 문자열 안의 괄호는 건너뛰고 찾는다.
#  bash 3.2 와 macOS awk 에서 돈다(python 필요 없음).
# ============================================================================

# vsc_part FILE MODE OPEN BEGIN END LINES NOTOPEN
#   MODE  on(칸을 넣거나 새로 바꿈) off(칸을 뺌) state(파일은 그대로, 상태만)
#   OPEN  "[" 또는 "{" : 파일의 맨 바깥 괄호
#   BEGIN END : 칸의 처음과 끝 표시 줄(주석). 처음 줄 뒤에는 " (plzrun-vscode-gcc-setup)" 이 붙는다
#   LINES : 칸 안에 넣을 줄이 든 파일(들여쓰기까지 그대로). // 로 시작하는 줄은 주석,
#           나머지는 항목이라 끝에 쉼표를 붙인다(칸 뒤에 아무 항목도 없으면 마지막 항목은 빼고)
#   NOTOPEN : 파일이 OPEN 으로 시작하지 않을 때 거절 이유
#   VP_STATUS 에 결과
#     on    : added(칸이 없었음) updated(옛 칸을 바꿈) unchanged(이미 같음) refused
#     off   : cleared absent refused
#     state : on folders(// vsc-folder: 줄이 있는 옛 칸) off refused
#   VP_WHY 에 refused 이유, VP_FOLDERS 에 옛 칸의 // vsc-folder: 목록(줄마다 하나)
vsc_part() {
    local file="$1" mode="$2" open="$3" bmark="$4" emark="$5" lines="$6" notopen="$7" close tmp st src nl=1
    VP_STATUS=""; VP_WHY=""; VP_FOLDERS=""
    if [ "$open" = "[" ]; then close="]"; else close="}"; fi
    if [ ! -f "$file" ]; then
        case "$mode" in
            on) mkdir -p "$(dirname "$file")" || { VP_STATUS=refused; VP_WHY="cannot make $(dirname "$file")"; return 0; } ;;
            off)   VP_STATUS=absent; return 0 ;;
            *)     VP_STATUS=off; return 0 ;;
        esac
        src=/dev/null; tmp="$file.vsc-new"
    else
        [ -s "$file" ] && [ "$(tail -c 1 "$file" | od -An -c | tr -d ' ')" != '\n' ] && nl=0
        src="$file"; tmp="$file.vsc-new"
    fi
    st="$file.vsc-status"
    awk -v lines="$lines" -v mode="$mode" -v st="$st" -v OPEN="$open" -v CLOSE="$close" -v NOTOPEN="$notopen" \
        -v BEGIN_MARK="$bmark" -v END_MARK="$emark" '
    function finish(status, why,   i) {
        print status > st; print why > st
        for (i = 1; i <= nf; i++) print F[i] > st
    }
    { L[++n] = $0 }
    END {
        # 1. 옛 칸 찾기 (// vsc-folder: 줄이 있으면 그 목록도)
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
        # 3. 맨 바깥 괄호와 그 뒤 첫 글자 찾기 (주석과 문자열은 건너뜀)
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
                    if (c != OPEN) break
                    li = i; ci = j; continue
                }
                nxt = c; break
            }
            if (first != "" && first != OPEN) break
        }
        if (first != "" && first != OPEN) { finish("refused", NOTOPEN); exit }
        # 4. 칸 안의 줄 읽기 (항목 줄의 번호를 기억해 마지막 항목의 쉼표를 정한다)
        nr = 0; last = 0
        while ((getline row < lines) > 0) {
            R[++nr] = row
            if (row !~ /^[ \t]*\/\//) { IT[nr] = 1; last = nr }
        }
        close(lines)
        empty = (first == "" || nxt == CLOSE)
        if (first == "") { for (i = 1; i <= m; i++) print M[i]; print OPEN; li = -1 }
        else for (i = 1; i < li; i++) print M[i]
        pre = (li > 0) ? substr(M[li], 1, ci) : ""; post = (li > 0) ? substr(M[li], ci + 1) : ""
        sp = (li > 0 && post !~ /^[ \t\r]*$/) ? 1 : 0
        if (li > 0) print (sp ? pre : M[li])
        print "    " BEGIN_MARK " (plzrun-vscode-gcc-setup)" (sp ? " [split]" : "")
        for (i = 1; i <= nr; i++) print R[i] ((IT[i] && (i < last || !empty)) ? "," : "")
        print "    " END_MARK
        if (sp) print post
        if (li > 0) for (i = li + 1; i <= m; i++) print M[i]
        else print CLOSE
        finish(b ? "replaced" : "added", "")
    }' "$src" > "$tmp"
    { IFS= read -r VP_STATUS; IFS= read -r VP_WHY || true; } < "$st"
    VP_FOLDERS="$(sed -n '3,$p' "$st")"
    rm -f "$st"
    case "$VP_STATUS" in
        refused|on|folders|off) rm -f "$tmp"; return 0 ;;
    esac
    VP_WHY=""
    # 원래 파일 끝에 줄바꿈이 없었으면 없게
    if [ "$nl" -eq 0 ]; then
        printf '%s' "$(cat "$tmp")" > "$tmp.1" && mv "$tmp.1" "$tmp"
    fi
    if [ -f "$file" ] && [ "$src" = "$file" ] && cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
        [ "$VP_STATUS" = replaced ] && VP_STATUS=unchanged
        return 0
    fi
    [ "$VP_STATUS" = replaced ] && VP_STATUS=updated
    mv "$tmp" "$file"
}
