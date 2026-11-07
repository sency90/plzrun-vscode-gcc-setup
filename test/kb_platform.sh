#!/usr/bin/env bash
# ============================================================================
#  task461: Shift+Esc 를 못 거는 곳(WSL, 모르는 운영체제)에서도 install.sh, vsc -shift-esc, uninstall.sh 가
#  이유 문구를 찍고 끝까지 가는지. 맥과 보통 리눅스는 예전처럼 keybindings.json 에 칸을 넣고 뺀다.
#  WSL 은 VSC_TEST_UNAME=Linux 와 "Microsoft" 가 든 가짜 /proc/version(VSC_TEST_PROC_VERSION)으로 흉내 낸다.
#  모두 임시 HOME 안에서만 돈다(실제 사용자 파일은 건드리지 않는다).
#  사용법:  bash test/kb_platform.sh      종료 코드 0 = 전부 통과
# ============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/vsc-kb-platform.XXXXXX")"
trap 'rm -rf "$T"' EXIT
unset VSC_KEYBINDINGS
mkdir -p "$T/stub"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/code"; chmod +x "$T/stub/code"      # code CLI 대신(확장 설치는 하는 척)
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 (root@x) #1 SMP\n' > "$T/proc-wsl"
printf 'Linux version 6.8.0-45-generic (buildd@x) #45-Ubuntu SMP\n' > "$T/proc-linux"
WHY_WSL="WSL: VSCode keeps its keybindings on the Windows side"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /' | tail -8; }
# run NAME HOME UNAME PROC CMD... : 출력은 $OUT, 종료 코드는 $RC
run() {
    local h="$2" u="$3" pv="$4"; shift 4
    OUT="$(env HOME="$h" PATH="$h/.local/bin:$T/stub:$PATH" VSC_TEST_UNAME="$u" VSC_TEST_PROC_VERSION="$pv" "$@" 2>&1 < /dev/null)"; RC=$?
}
expect() {   # expect NAME RC 글자...   : 종료 코드와 모든 글자가 출력에 있고 unbound 오류가 없어야 한다
    local name="$1" want="$2"; shift 2
    if [ "$RC" != "$want" ]; then bad "$name (exit $RC, want $want)" "$OUT"; return; fi
    case "$OUT" in *"unbound variable"*) bad "$name (unbound variable)" "$OUT"; return ;; esac
    local s; for s in "$@"; do case "$OUT" in *"$s"*) : ;; *) bad "$name (no: $s)" "$OUT"; return ;; esac; done
    ok "$name"
}

echo "== WSL"
H="$T/wsl"; mkdir -p "$H"
run wsl "$H" Linux "$T/proc-wsl" bash "$REPO/install.sh"
expect "WSL install.sh: Shift+Esc 는 이유와 함께 안내만, done 까지" 0 "Shift+Esc was not set up ($WHY_WSL)" "the list:" "done."
[ -z "$(find "$H" -name keybindings.json)" ] && ok "WSL install.sh: keybindings.json 을 만들지 않음" || bad "WSL install.sh: keybindings.json 이 생김"
run wsl "$H" Linux "$T/proc-wsl" "$H/.local/bin/vsc" -shift-esc on
expect "WSL vsc -shift-esc on: 이유 문구로 끝남" 1 "Shift+Esc cannot be changed here ($WHY_WSL)"
run wsl "$H" Linux "$T/proc-wsl" "$H/.local/bin/vsc" -shift-esc off
expect "WSL vsc -shift-esc off: 이유 문구로 끝남" 1 "Shift+Esc cannot be changed here ($WHY_WSL)"
run wsl "$H" Linux "$T/proc-wsl" bash "$REPO/uninstall.sh"
expect "WSL uninstall.sh: 이유 문구로 끝남" 0 "Shift+Esc: nothing to remove ($WHY_WSL)"

echo "== 모르는 운영체제"
H="$T/bsd"; mkdir -p "$H"
run bsd "$H" FreeBSD "$T/proc-linux" bash "$REPO/install.sh"
expect "FreeBSD install.sh: 이유 문구, done 까지" 0 "Shift+Esc was not set up (unsupported system FreeBSD)" "done."

echo "== 맥(그대로)"
H="$T/mac"; mkdir -p "$H"; KB="$H/Library/Application Support/Code/User/keybindings.json"
run mac "$H" Darwin "$T/proc-linux" bash "$REPO/install.sh"
expect "Mac install.sh: 칸을 넣음" 0 "added the vsc part to $KB" "done."
grep -q "// >>> vsc shift+escape" "$KB" 2>/dev/null && ok "Mac: keybindings.json 에 칸" || bad "Mac: keybindings.json 에 칸이 없음"
run mac "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -shift-esc off
expect "Mac vsc -shift-esc off" 0 "$KB"
run mac "$H" Darwin "$T/proc-linux" "$H/.local/bin/vsc" -shift-esc on
expect "Mac vsc -shift-esc on" 0 "$KB"
run mac "$H" Darwin "$T/proc-linux" bash "$REPO/uninstall.sh"
expect "Mac uninstall.sh: 칸을 뺌" 0 "removed the Shift+Esc part from $KB"

echo "== 보통 리눅스(그대로)"
H="$T/linux"; mkdir -p "$H"; KB="$H/.config/Code/User/keybindings.json"
run linux "$H" Linux "$T/proc-linux" bash "$REPO/install.sh"
expect "Linux install.sh: 칸을 넣음" 0 "added the vsc part to $KB" "done."
run linux "$H" Linux "$T/proc-linux" bash "$REPO/uninstall.sh"
expect "Linux uninstall.sh: 칸을 뺌" 0 "removed the Shift+Esc part from $KB"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
