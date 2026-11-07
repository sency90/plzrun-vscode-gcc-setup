#!/usr/bin/env bash
# ============================================================================
#  task465: C/C++ 코드 조각 제안(cpptools 의 if, for, class 같은 스니펫)을 끄는 설정
#  "C_Cpp.suggestSnippets": false 를 install.sh 가 넣고, vsc -cpp-snippets on|off 가 바꾸고,
#  uninstall.sh 가 뺀다. 사용자의 다른 설정은 그대로, 빼면 원래 파일과 바이트까지 같다.
#    맥     ~/Library/Application Support/Code/User/settings.json
#    리눅스 ~/.config/Code/User/settings.json
#    WSL    ~/.vscode-server/data/Machine/settings.json (Remote-WSL 의 "원격 설정". Windows 쪽 파일은 안 건드림)
#  운영체제 흉내는 test/kb_platform.sh 와 같다(VSC_TEST_UNAME, VSC_TEST_PROC_VERSION, 임시 HOME).
#  사용법:  bash test/cpp_snippets.sh      종료 코드 0 = 전부 통과
# ============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERE="$REPO/test"
T="$(mktemp -d "${TMPDIR:-/tmp}/vsc-cpp-snippets.XXXXXX")"
trap 'rm -rf "$T"' EXIT
unset VSC_KEYBINDINGS VSC_SETTINGS VSCODE_AGENT_FOLDER
mkdir -p "$T/stub"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/code"; chmod +x "$T/stub/code"      # code CLI 대신(확장 설치는 하는 척)
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 (root@x) #1 SMP\n' > "$T/proc-wsl"
printf 'Linux version 6.8.0-45-generic (buildd@x) #45-Ubuntu SMP\n' > "$T/proc-linux"
FX="$HERE/fixtures/settings-user.jsonc"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /' | tail -8; }
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
# js FILE KEY : VSCode 처럼 읽은(주석과 끝 쉼표 허용) 값. 키가 없으면 MISSING, 못 읽으면 BAD
js() {
    python3 -I - "$1" "$2" "$HERE" <<'EOF'
import json, re, sys
sys.path.insert(0, sys.argv[3])
from kb_check import strip_comments
try:
    s = strip_comments(open(sys.argv[1], encoding="utf-8").read())
    s = re.sub(r",(\s*[}\]])", r"\1", s)
    v = json.loads(s) if s.strip() else {}
except Exception as e:
    print("BAD", e); sys.exit(0)
print(json.dumps(v.get(sys.argv[2], "MISSING")) if isinstance(v, dict) else "BAD not an object")
EOF
}
# same_keys FILE ORIG : 사용자 키와 값이 원래 파일과 모두 같다(우리 키 하나만 더해짐)
same_keys() {
    python3 -I - "$1" "$2" "$HERE" <<'EOF'
import json, re, sys
sys.path.insert(0, sys.argv[3])
from kb_check import strip_comments
def load(p):
    s = re.sub(r",(\s*[}\]])", r"\1", strip_comments(open(p, encoding="utf-8").read()))
    return json.loads(s) if s.strip() else {}
a, b = load(sys.argv[1]), load(sys.argv[2])
a.pop("C_Cpp.suggestSnippets", None)
print("same" if a == {k: v for k, v in b.items() if k != "C_Cpp.suggestSnippets"} else "differ")
EOF
}
check_file() {   # check_file NAME FILE 기대값(false|MISSING)
    local v; v="$(js "$2" C_Cpp.suggestSnippets)"
    [ "$v" = "$3" ] && ok "$1: C_Cpp.suggestSnippets = $3" || bad "$1: C_Cpp.suggestSnippets = $v (want $3)" "$(cat "$2" 2>/dev/null)"
}
same_bytes() {   # same_bytes NAME A B
    cmp -s "$2" "$3" && ok "$1" || bad "$1" "$(diff "$3" "$2")"
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
    expect "$plat install.sh: 코드 조각 제안을 끈다고 알림, done 까지" 0 "C/C++ code snippets (if, for, class ...) are off" "$S" "done."
    check_file "$plat install.sh" "$S" false
    r="$(same_keys "$S" "$FX")"; [ "$r" = same ] && ok "$plat install.sh: 사용자 설정 그대로" || bad "$plat install.sh: 사용자 설정이 바뀜" "$(cat "$S")"
    cp "$S" "$T/$plat-after.json"
    run "$H" "$U" "$PV" bash "$REPO/install.sh"
    same_bytes "$plat install.sh 두 번: 파일 그대로" "$S" "$T/$plat-after.json"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -cpp-snippets on
    expect "$plat vsc -cpp-snippets on" 0 "cpp-snippets: off -> on" "$S"
    same_bytes "$plat vsc -cpp-snippets on: 원래 파일과 같음" "$S" "$FX"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -cpp-snippets off
    expect "$plat vsc -cpp-snippets off" 0 "cpp-snippets: on -> off" "$S"
    same_bytes "$plat vsc -cpp-snippets off: install.sh 뒤와 같음" "$S" "$T/$plat-after.json"
    run "$H" "$U" "$PV" "$H/.local/bin/vsc" -cpp-snippets off
    expect "$plat vsc -cpp-snippets off 두 번" 0 "nothing changed in $S"
    run "$H" "$U" "$PV" bash "$REPO/uninstall.sh"
    expect "$plat uninstall.sh: 설정을 뺐다고 알림" 0 "C/C++ code snippets are back to the VSCode default" "$S"
    same_bytes "$plat uninstall.sh: 원래 파일과 바이트까지 같음" "$S" "$FX"
done

echo "== WSL: Windows 쪽 설정과 이 PC 의 맥/리눅스 자리는 만들지 않는다"
[ -z "$(find "$T/wsl" -path '*Code/User*')" ] && ok "WSL: Code/User 아래 파일 없음" || bad "WSL: Code/User 아래 파일이 생김" "$(find "$T/wsl" -path '*Code/User*')"
H="$T/wsl-agent"; mkdir -p "$H"
OUT="$(env HOME="$H" PATH="$H/.local/bin:$T/stub:$PATH" VSC_TEST_UNAME=Linux VSC_TEST_PROC_VERSION="$T/proc-wsl" VSCODE_AGENT_FOLDER="$H/agent" bash "$REPO/install.sh" 2>&1 < /dev/null)"; RC=$?
expect "WSL VSCODE_AGENT_FOLDER: 그 폴더의 data/Machine 에 넣음" 0 "$H/agent/data/Machine/settings.json"
check_file "WSL VSCODE_AGENT_FOLDER" "$H/agent/data/Machine/settings.json" false

echo "== 파일 모양"
H="$T/shape"; mkdir -p "$H"; S="$H/Library/Application Support/Code/User/settings.json"
run "$H" Darwin "$T/proc-linux" bash "$REPO/install.sh"
expect "파일이 없으면 만든다" 0 "$S"
check_file "새 파일" "$S" false
for body in '{}' '{"editor.fontSize": 14}' '{
    "editor.fontSize": 14,
}' '// my settings
{
}'; do
    printf '%s' "$body" > "$T/shape.json"; cp "$T/shape.json" "$S"
    run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippets off
    name="$(printf '%s' "$body" | tr '\n' ' ')"
    expect "모양 [$name] off" 0 "$S"
    check_file "모양 [$name]" "$S" false
    r="$(same_keys "$S" "$T/shape.json")"; [ "$r" = same ] && ok "모양 [$name]: 다른 키 그대로" || bad "모양 [$name]: 다른 키가 바뀜" "$(cat "$S")"
    run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippets on
    same_bytes "모양 [$name] on: 원래 바이트" "$S" "$T/shape.json"
done
printf '[1, 2]\n' > "$S"; cp "$S" "$T/arr.json"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippets off
expect "객체가 아닌 파일은 거절" 1 "does not start with a JSON object {"
same_bytes "거절하면 파일 그대로" "$S" "$T/arr.json"
printf '{\n    "C_Cpp.suggestSnippets": true\n}\n' > "$S"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippets off
expect "사용자가 직접 C_Cpp.suggestSnippets 를 두었으면 그쪽이 이긴다고 알림" 0 "your own \"C_Cpp.suggestSnippets\"" "wins"

echo "== 값 검사"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippets maybe
expect "모르는 값" 1 "unknown value for -cpp-snippets: 'maybe'"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -cpp-snippet off
expect "옵션 이름 오타는 Did you mean" 1 "-cpp-snippets"
run "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" --help
expect "--help 에 설명" 0 "-cpp-snippets <on|off>"

echo "== Shift+Esc 는 예전 그대로(keybindings.json)"
H="$T/kb"; mkdir -p "$H"; KB="$H/Library/Application Support/Code/User/keybindings.json"
run "$H" Darwin "$T/proc-linux" bash "$REPO/install.sh"
expect "맥 install.sh: Shift+Esc 칸도 넣음" 0 "added the vsc part to $KB"
run "$H" Linux "$T/proc-wsl" bash "$REPO/install.sh"
expect "WSL install.sh: Shift+Esc 는 안내만" 0 "Shift+Esc was not set up (WSL: VSCode keeps its keybindings on the Windows side)"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
