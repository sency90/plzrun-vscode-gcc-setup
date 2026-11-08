#!/usr/bin/env bash
# ============================================================================
#  task469: 한글 입력 때 커서가 튀고 글자가 두 번 써지는 것을 막는 설정
#  "editor.editContext": false 를 install.sh 가 넣고, vsc -edit-context on|off 가 바꾸고,
#  uninstall.sh 가 뺀다. 자리는 C/C++ 코드 조각 칸(task465)과 같은 settings.json 이다.
#    맥     ~/Library/Application Support/Code/User/settings.json
#    리눅스 ~/.config/Code/User/settings.json
#    WSL    ~/.vscode-server/data/Machine/settings.json (Remote-WSL 의 "원격 설정". Windows 쪽 파일은 안 건드림)
#  한 파일에 vsc 칸이 둘(edit-context, cpp-snippets) 들어가므로, 어느 순서로 넣고 빼도
#  JSON 이 깨지지 않고 둘 다 빼면 원래 바이트로 돌아오는지도 본다.
#  운영체제 흉내는 test/cpp_snippets.sh 와 같다(VSC_TEST_UNAME, VSC_TEST_PROC_VERSION, 임시 HOME).
#  사용법:  bash test/edit_context.sh      종료 코드 0 = 전부 통과
# ============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERE="$REPO/test"
T="$(mktemp -d "${TMPDIR:-/tmp}/vsc-edit-context.XXXXXX")"
trap 'rm -rf "$T"' EXIT
unset VSC_KEYBINDINGS VSC_SETTINGS VSCODE_AGENT_FOLDER
mkdir -p "$T/stub"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/code"; chmod +x "$T/stub/code"      # code CLI 대신(확장 설치는 하는 척)
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 (root@x) #1 SMP\n' > "$T/proc-wsl"
printf 'Linux version 6.8.0-45-generic (buildd@x) #45-Ubuntu SMP\n' > "$T/proc-linux"
FX="$HERE/fixtures/settings-user.jsonc"
EC=editor.editContext
CS=C_Cpp.suggestSnippets
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /' | tail -12; }
run() {   # run HOME UNAME PROC CMD... : 출력은 $OUT, 종료 코드는 $RC
    local h="$1" u="$2" pv="$3"; shift 3
    OUT="$(env HOME="$h" PATH="$h/.local/bin:$T/stub:$PATH" VSC_TEST_UNAME="$u" VSC_TEST_PROC_VERSION="$pv" "$@" 2>&1 < /dev/null)"; RC=$?
}
expect() {   # expect NAME RC 글자...
    local name="$1" want="$2"; shift 2
    if [ "$RC" != "$want" ]; then bad "$name (exit $RC, want $want)" "$OUT"; return; fi
    case "$OUT" in *"unbound variable"*) bad "$name (unbound variable)" "$OUT"; return ;; esac
    local s; for s in "$@"; do case "$OUT" in *"$s"*) : ;; *) bad "$name (no: $s)" "$OUT"; return ;; esac; done
    ok "$name"
}
# js FILE KEY [strict] : VSCode 처럼 읽은(주석 허용) 값. strict 가 아니면 끝 쉼표도 허용.
#   키가 없으면 MISSING, 못 읽으면 BAD
js() {
    python3 -I - "$1" "$2" "$HERE" "${3:-}" <<'EOF'
import json, re, sys
sys.path.insert(0, sys.argv[3])
from kb_check import strip_comments
try:
    s = strip_comments(open(sys.argv[1], encoding="utf-8").read())
    if sys.argv[4] != "strict":
        s = re.sub(r",(\s*[}\]])", r"\1", s)
    v = json.loads(s) if s.strip() else {}
except Exception as e:
    print("BAD", e); sys.exit(0)
print(("MISSING" if sys.argv[2] not in v else json.dumps(v[sys.argv[2]])) if isinstance(v, dict) else "BAD not an object")
EOF
}
# same_keys FILE ORIG : 사용자 키와 값이 원래 파일과 모두 같다(vsc 키 둘만 더해짐)
same_keys() {
    python3 -I - "$1" "$2" "$HERE" <<'EOF'
import json, re, sys
sys.path.insert(0, sys.argv[3])
from kb_check import strip_comments
def load(p):
    s = re.sub(r",(\s*[}\]])", r"\1", strip_comments(open(p, encoding="utf-8").read()))
    v = json.loads(s) if s.strip() else {}
    for k in ("C_Cpp.suggestSnippets", "editor.editContext"):
        v.pop(k, None)
    return v
print("same" if load(sys.argv[1]) == load(sys.argv[2]) else "differ")
EOF
}
check_key() {   # check_key NAME FILE KEY 기대값(false|MISSING) [strict]
    local v; v="$(js "$2" "$3" "${5:-}")"
    [ "$v" = "$4" ] && ok "$1: $3 = $4${5:+ ($5)}" || bad "$1: $3 = $v (want $4${5:+, $5})" "$(cat "$2" 2>/dev/null)"
}
same_bytes() {   # same_bytes NAME A B
    cmp -s "$2" "$3" && ok "$1" || bad "$1" "$(diff "$3" "$2")"
}
user_kept() {   # user_kept NAME FILE ORIG
    local r; r="$(same_keys "$2" "$3")"
    [ "$r" = same ] && ok "$1: 사용자 설정 그대로" || bad "$1: 사용자 설정이 바뀜" "$(cat "$2")"
}

for plat in mac linux wsl; do
    H="$T/$plat"; mkdir -p "$H"
    case "$plat" in
        mac)   U=Darwin; PV="$T/proc-linux"; S="$H/Library/Application Support/Code/User/settings.json" ;;
        linux) U=Linux;  PV="$T/proc-linux"; S="$H/.config/Code/User/settings.json" ;;
        wsl)   U=Linux;  PV="$T/proc-wsl";   S="$H/.vscode-server/data/Machine/settings.json" ;;
    esac
    echo "== $plat ($S)"
    mkdir -p "$(dirname "$S")"; cp "$FX" "$S"
    run "$H" "$U" "$PV" bash "$REPO/install.sh"
    expect "$plat install.sh: EditContext 를 끈다고 알림, done 까지" 0 "EditContext is off" "$S" "done."
    check_key "$plat install.sh" "$S" "$EC" false strict
    check_key "$plat install.sh" "$S" "$CS" false strict
    user_kept "$plat install.sh" "$S" "$FX"
    cp "$S" "$T/$plat-after.json"
    run "$H" "$U" "$PV" bash "$REPO/install.sh"
    same_bytes "$plat install.sh 두 번: 파일 그대로" "$S" "$T/$plat-after.json"

    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -edit-context on
    expect "$plat vsc -edit-context on" 0 "edit-context: off -> on" "$S"
    check_key "$plat vsc -edit-context on" "$S" "$EC" MISSING strict
    check_key "$plat vsc -edit-context on: 코드 조각 칸은 그대로" "$S" "$CS" false strict
    user_kept "$plat vsc -edit-context on" "$S" "$FX"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -edit-context on
    expect "$plat vsc -edit-context on 두 번" 0 "nothing changed in $S (edit-context is already on)"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -edit-context off
    expect "$plat vsc -edit-context off" 0 "edit-context: on -> off" "$S"
    same_bytes "$plat vsc -edit-context off: install.sh 뒤와 같음" "$S" "$T/$plat-after.json"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -edit-context off
    expect "$plat vsc -edit-context off 두 번" 0 "nothing changed in $S (edit-context is already off)"

    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -cpp-snippets on
    expect "$plat vsc -cpp-snippets on" 0 "cpp-snippets: off -> on"
    check_key "$plat vsc -cpp-snippets on: EditContext 칸은 그대로" "$S" "$EC" false strict
    check_key "$plat vsc -cpp-snippets on" "$S" "$CS" MISSING strict
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -edit-context on
    same_bytes "$plat 칸 둘 다 뺌: 원래 파일과 같음" "$S" "$FX"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -edit-context off -cpp-snippets off
    expect "$plat vsc -edit-context off -cpp-snippets off 한 번에" 0 "edit-context: on -> off" "cpp-snippets: on -> off"
    same_bytes "$plat 다시 둘 다 켬: install.sh 뒤와 같음" "$S" "$T/$plat-after.json"

    run "$H" "$U" "$PV" bash "$REPO/uninstall.sh"
    expect "$plat uninstall.sh: 설정을 뺐다고 알림" 0 "EditContext is back to the VSCode default" "$S"
    same_bytes "$plat uninstall.sh: 원래 파일과 바이트까지 같음" "$S" "$FX"
done

echo "== WSL: Windows 쪽 설정과 이 PC 의 맥/리눅스 자리는 만들지 않는다"
[ -z "$(find "$T/wsl" -path '*Code/User*')" ] && ok "WSL: Code/User 아래 파일 없음" || bad "WSL: Code/User 아래 파일이 생김" "$(find "$T/wsl" -path '*Code/User*')"
H="$T/wsl-agent"; mkdir -p "$H"
OUT="$(env HOME="$H" PATH="$H/.local/bin:$T/stub:$PATH" VSC_TEST_UNAME=Linux VSC_TEST_PROC_VERSION="$T/proc-wsl" VSCODE_AGENT_FOLDER="$H/agent" bash "$REPO/install.sh" 2>&1 < /dev/null)"; RC=$?
expect "WSL VSCODE_AGENT_FOLDER: 그 폴더의 data/Machine 에 넣음" 0 "$H/agent/data/Machine/settings.json"
check_key "WSL VSCODE_AGENT_FOLDER" "$H/agent/data/Machine/settings.json" "$EC" false strict

echo "== v1.5.0 이 넣은 코드 조각 칸만 있는 파일"
H="$T/v150"; mkdir -p "$H"; S="$H/Library/Application Support/Code/User/settings.json"
mkdir -p "$(dirname "$S")"
{ sed -n 1p "$FX"; echo '{'
  echo '    // >>> vsc cpp-snippets (plzrun-vscode-gcc-setup)'
  echo '    // C/C++ code snippets (if, for, class ...) are not suggested. vsc writes this part; do not edit it.'
  echo '    // Turn them back on with: vsc -cpp-snippets on   (uninstall.sh also takes this part out)'
  echo '    "C_Cpp.suggestSnippets": false,'
  echo '    // <<< vsc cpp-snippets'
  sed -n '3,$p' "$FX"; } > "$S"
run "$H" Darwin "$T/proc-linux" bash "$REPO/install.sh"
expect "v1.5.0 파일에 install.sh: EditContext 칸을 더함" 0 "EditContext is off" "added the vsc part"
check_key "v1.5.0 파일" "$S" "$EC" false strict
check_key "v1.5.0 파일" "$S" "$CS" false strict
user_kept "v1.5.0 파일" "$S" "$FX"
[ "$(grep -c '// >>> vsc cpp-snippets' "$S")" = 1 ] && ok "v1.5.0 파일: 코드 조각 칸은 하나" || bad "v1.5.0 파일: 코드 조각 칸이 하나가 아님" "$(cat "$S")"
run "$H" Darwin "$T/proc-linux" bash "$REPO/uninstall.sh"
same_bytes "v1.5.0 파일 uninstall.sh: 처음 사용자 파일과 같음" "$S" "$FX"

echo "== 파일 모양과 넣고 빼는 순서 (칸 둘)"
H="$T/shape"; mkdir -p "$H"; S="$H/Library/Application Support/Code/User/settings.json"
run "$H" Darwin "$T/proc-linux" bash "$REPO/install.sh"
expect "파일이 없으면 만든다" 0 "$S"
check_key "새 파일" "$S" "$EC" false strict
check_key "새 파일" "$S" "$CS" false strict
n=0
for body in '{}' '{"editor.fontSize": 14}' '{ "editor.fontSize": 14 }
' '{
    "editor.fontSize": 14
}
' '// my settings
{
}
' '{
}'; do
    n=$((n + 1))
    printf '%s' "$body" > "$T/shape.json"
    name="$(printf '%s' "$body" | tr '\n' ' ')"
    # 순서: (a b 를 켜고) (c 를 끄고) (d 를 끔). 앞이 먼저 들어간 칸
    for order in "cpp-snippets edit-context cpp-snippets edit-context" \
                 "cpp-snippets edit-context edit-context cpp-snippets" \
                 "edit-context cpp-snippets edit-context cpp-snippets" \
                 "edit-context cpp-snippets cpp-snippets edit-context"; do
        set -- $order
        tag="모양$n [$name] $1>$2 넣고 $3>$4 빼기"
        cp "$T/shape.json" "$S"
        run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -"$1" off
        run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -"$2" off
        check_key "$tag: 둘 다" "$S" "$EC" false strict
        check_key "$tag: 둘 다" "$S" "$CS" false strict
        user_kept "$tag: 둘 다" "$S" "$T/shape.json"
        run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -"$3" on
        expect "$tag: $3 on" 0 "$3: off -> on"
        if [ "$3" = edit-context ]; then k1="$EC"; k2="$CS"; else k1="$CS"; k2="$EC"; fi
        check_key "$tag: 하나 뺀 뒤" "$S" "$k1" MISSING strict
        check_key "$tag: 하나 뺀 뒤" "$S" "$k2" false strict
        user_kept "$tag: 하나 뺀 뒤" "$S" "$T/shape.json"
        run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -"$4" on
        same_bytes "$tag: 원래 바이트" "$S" "$T/shape.json"
    done
done
set --
printf '[1, 2]\n' > "$S"; cp "$S" "$T/arr.json"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -edit-context off
expect "객체가 아닌 파일은 거절" 1 "does not start with a JSON object {"
same_bytes "거절하면 파일 그대로" "$S" "$T/arr.json"
printf '{\n    "editor.editContext": true\n}\n' > "$S"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -edit-context off
expect "사용자가 직접 editor.editContext 를 두었으면 그쪽이 이긴다고 알림" 0 "your own \"editor.editContext\"" "wins"
printf '{\n    // >>> vsc edit-context (plzrun-vscode-gcc-setup)\n    "editor.editContext": false\n}\n' > "$S"; cp "$S" "$T/broken.json"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippets off
expect "다른 칸의 끝 줄이 없으면 거절" 1 "no end line"
same_bytes "다른 칸이 깨져 거절하면 파일 그대로" "$S" "$T/broken.json"

echo "== 값 검사"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -edit-context maybe
expect "모르는 값" 1 "unknown value for -edit-context: 'maybe'"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -edit-contxt off
expect "옵션 이름 오타는 Did you mean" 1 "-edit-context"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" --edit-context off
expect "두 줄 대시는 한 줄로 안내" 1 "options with a value use one dash: -edit-context"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" --help
expect "--help 에 설명" 0 "-edit-context <on|off>"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
