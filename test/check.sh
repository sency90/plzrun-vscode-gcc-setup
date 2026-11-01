#!/usr/bin/env bash
# ============================================================================
#  vsc 시험: 복사본 폴더에서 모든 명령을 실제로 돌려 출력을 남긴다.
#  사용법:  bash test/check.sh <ex 문제 폴더> <poj 문제 폴더>
#    예)    bash test/check.sh ~/github/sw_expert/.../EX_..._1 ~/github/poj/14216
#  원본 폴더는 읽기만 한다. 복사본은 test/work/ (gitignore) 에 만든다.
#  poj 문제 폴더에는 <번호>.cpp, in, in2 가 있어야 한다.
# ============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
EX_SRC="${1:?usage: check.sh <ex folder> <poj problem folder>}"
POJ_SRC="${2:?usage: check.sh <ex folder> <poj problem folder>}"
PROB="$(basename "$POJ_SRC")"

WORK="$HERE/work"
rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/ex" "$WORK/poj/$PROB"
ln -s "$REPO/setup.sh" "$WORK/bin/vsc"
ln -s "$REPO/setup.sh" "$WORK/bin/plzrun-vscode-gcc-setup"
export PATH="$WORK/bin:$PATH"
# Shift+Esc 칸은 시험용 keybindings.json 에만 쓴다 (실제 사용자 파일은 절대 건드리지 않는다)
mkdir -p "$WORK/kb"
export VSC_KEYBINDINGS="$WORK/kb/keybindings.json"
cp "$HERE/fixtures/keybindings-user.jsonc" "$VSC_KEYBINDINGS"

# 복사: ex 는 소스와 기존 .vscode, poj 는 소스와 입력 파일만 (빌드 산출물 제외)
cp -p "$EX_SRC"/*.cpp "$WORK/ex/"
[ -f "$EX_SRC/main.h" ] && cp -p "$EX_SRC"/*.h "$WORK/ex/"
[ -d "$EX_SRC/.vscode" ] && cp -Rp "$EX_SRC/.vscode" "$WORK/ex/"
cp -p "$POJ_SRC"/*.cpp "$POJ_SRC"/in* "$WORK/poj/$PROB/"

SIM="python3 -I $HERE/vscode_sim.py"
# 입력이 없는 경우(터미널에서 읽기)가 시험을 멈추지 않게 표준 입력은 /dev/null
run() { echo; echo "\$ $*"; "$@" < /dev/null; echo "[exit $?]"; }

echo "################ poj copy: $WORK/poj"
cd "$WORK/poj"
run vsc
run vsc
run vsc -lang c++17
run vsc -lang c++17
run vsc -stdin in2
run vsc -stdout out2
run vsc
run vsc -stdin in3
run vsc -stdin default -stdout default
run vsc -lang default
run vsc -stdn in2
run vsc -lang c++41
run vsc -lang c++1
run vsc -lang
run vsc -stdin
run vsc -stdout -lang c++17
run vsc -init
run vsc --lang c++17
run vsc --inti
run vsc -std x
run vsc init
run vsc -stdout "$PROB.cpp"
run vsc -stdout in
run vsc --ex --single
run vsc --remove -lang c++17
run vsc -xyz
run vsc —init
run vsc -lang c++20 -stdin in2
run vsc --init
run vsc --init
cd "$WORK/poj/$PROB"
run vsc -stdin in2
cd "$WORK/poj"

echo; echo "################ poj: build and run with the generated tasks.json"
F="$WORK/poj/$PROB/$PROB.cpp"
run vsc --init
run $SIM task . "$F" "run release"
run vsc -stdin in2
run $SIM task . "$F" "run release"
run vsc -stdout out2
run $SIM task . "$F" "run release"
echo "\$ cat $PROB/out2"; cat "$WORK/poj/$PROB/out2"
run vsc -stdin in9
run $SIM task . "$F" "run release"
run vsc --init

echo; echo "################ poj: F5 (macOS lldb-mi, driven like cpptools)"
run $SIM f5-lldb . "$F"
run vsc -stdin in2
run $SIM f5-lldb . "$F"
run vsc -stdout out2
rm -f "$WORK/poj/$PROB/out2"
run $SIM f5-lldb . "$F"
echo "\$ cat $PROB/out2"; cat "$WORK/poj/$PROB/out2"
run $SIM f5-gdb . "$F"
run vsc -stdin in9 -stdout default
run $SIM f5-lldb . "$F"
run vsc --init

echo; echo "################ poj: Ctrl+F5 (Run Without Debugging, command line as cpptools builds it)"
run $SIM ctrl-f5 . "$F" osx /bin/zsh
run vsc -stdin in2
run $SIM ctrl-f5 . "$F" osx /bin/zsh
run vsc -stdout out2
rm -f "$WORK/poj/$PROB/out2"
run $SIM ctrl-f5 . "$F" osx /bin/zsh
echo "\$ cat $PROB/out2"; cat "$WORK/poj/$PROB/out2"
rm -f "$WORK/poj/$PROB/out2"
run $SIM ctrl-f5 . "$F" linux /bin/bash
echo "\$ cat $PROB/out2"; cat "$WORK/poj/$PROB/out2"
run vsc -stdin in9 -stdout default
run $SIM ctrl-f5 . "$F" osx /bin/zsh
run vsc --init

echo; echo "################ poj: --single / --ex switching, --remove"
run vsc --ex
run vsc --single
run vsc --remove
run vsc --remove
run vsc -lang c++17
run vsc

echo; echo "################ ex copy: $WORK/ex (has a .vscode made by the old version)"
cd "$WORK/ex"
U="$WORK/ex/user.cpp"
run plzrun-vscode-gcc-setup
run vsc
run vsc -lang c++17
run vsc -lang c++14
run vsc -stdin in2
run vsc --init
run $SIM task . "$U" "run release"
run $SIM task . "$U" "run exam (timed)"
run $SIM f5-lldb . "$U"
run $SIM ctrl-f5 . "$U" osx /bin/zsh
run vsc --single
run vsc --ex
run vsc --remove

echo; echo "################ foreign tasks.json is kept unless --force"
mkdir -p "$WORK/foreign/.vscode"
cd "$WORK/foreign"
mkdir -p .vscode; printf '{ "version": "2.0.0", "tasks": [] }\n' > .vscode/tasks.json
run vsc
run vsc -lang c++17
run vsc --force
run vsc --remove
mkdir -p .vscode; printf '{ "version": "2.0.0", "tasks": [] }\n' > .vscode/tasks.json
run vsc --remove
echo "\$ ls .vscode"; ls .vscode

echo; echo "################ Shift+Esc = Esc (user keybindings.json, test copy: $VSC_KEYBINDINGS)"
KBC="python3 -I $HERE/kb_check.py"
KB="$VSC_KEYBINDINGS"
TSV="$REPO/templates/shift-esc.tsv"
ORIG="$WORK/kb/orig.json"
cp "$HERE/fixtures/keybindings-user.jsonc" "$KB"; cp "$KB" "$ORIG"
same_as() { if cmp -s "$1" "$2"; then echo "same bytes: $(basename "$1") = $(basename "$2")"; else echo "DIFFERENT: $1 $2"; return 1; fi; }
cd "$WORK/poj"
run vsc
run $KBC parse "$KB"
run $KBC same-user "$KB" "$ORIG"
run $KBC ours "$KB" "$TSV" "$WORK/poj"
cp "$KB" "$WORK/kb/after-poj.json"
run vsc
run vsc -lang c++17
run same_as "$KB" "$WORK/kb/after-poj.json"
cd "$WORK/ex"
run vsc
run $KBC ours "$KB" "$TSV" "$WORK/poj" "$WORK/ex"
run $KBC same-user "$KB" "$ORIG"
run $KBC simulate "$KB" "$TSV" "$WORK/poj" 20000
run $KBC simulate "$KB" "$TSV" "$WORK/ex" 5000
# 같은 상태들을 설치된 VSCode 의 조건식 분석기와 평가기로 (node 가 없거나 VSCode 가 없으면 건너뜀)
if command -v node >/dev/null 2>&1; then
    $KBC states "$TSV" "$WORK/poj" 20000 > "$WORK/kb/states.json"
    run node "$HERE/vscode_when.js" "$KB" "$TSV" "$WORK/kb/states.json" "$WORK/poj"
else
    echo "node not found: skipped the check with VSCode's own when-clause parser"
fi
cd "$WORK/poj"
run vsc --remove
run $KBC ours "$KB" "$TSV" "$WORK/ex"
cd "$WORK/ex"
run vsc --remove
run same_as "$KB" "$ORIG"
echo "--- no keybindings.json yet"
rm -f "$KB"
cd "$WORK/poj"
run vsc
run $KBC parse "$KB"
run $KBC ours "$KB" "$TSV" "$WORK/poj"
run vsc --remove
run $KBC parse "$KB"
echo "--- empty array [] without a final newline"
printf '[]' > "$KB"; cp "$KB" "$ORIG"
run vsc
run $KBC parse "$KB"
run vsc --remove
run same_as "$KB" "$ORIG"
echo "--- an entry on the same line as ["
printf '[{ "key": "f1", "command": "x" }]\n' > "$KB"; cp "$KB" "$ORIG"
run vsc
run $KBC same-user "$KB" "$ORIG"
run $KBC ours "$KB" "$TSV" "$WORK/poj"
run vsc --remove
run same_as "$KB" "$ORIG"
echo "--- not a JSON array: left alone"
printf '{ "oops": 1 }\n' > "$KB"; cp "$KB" "$ORIG"
run vsc
run same_as "$KB" "$ORIG"
echo "--- a begin line without an end line: left alone"
printf '[\n    // >>> vsc shift+escape (plzrun-vscode-gcc-setup)\n]\n' > "$KB"; cp "$KB" "$ORIG"
run vsc
run same_as "$KB" "$ORIG"
echo "--- uninstall.sh takes the whole part out (fake HOME)"
cp "$HERE/fixtures/keybindings-user.jsonc" "$KB"; cp "$KB" "$ORIG"
run vsc
cd "$WORK/ex"; run vsc
mkdir -p "$WORK/home"
run env HOME="$WORK/home" bash "$REPO/uninstall.sh"
run same_as "$KB" "$ORIG"
cd "$WORK/poj"; run vsc --remove; cd "$WORK/ex"; run vsc --remove
cp "$HERE/fixtures/keybindings-user.jsonc" "$KB"

echo; echo "################ help"
run vsc --help
