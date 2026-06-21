#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup — 현재 폴더에 sw_expert C/C++ .vscode 컴파일 세팅 생성
#  사용법:  (프로젝트 폴더에서)  plzrun-vscode-gcc-setup
#           또는                 bash /path/to/setup.sh  [target_dir]
#  생성: ./.vscode/tasks.json (exam/release/debug 빌드 + run) , launch.json (F5 디버그)
# ============================================================================
set -euo pipefail

log()  { printf '\033[1;32m[vsc-gcc]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vsc-gcc:warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[vsc-gcc:err]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 스크립트 실제 위치 해석 (심링크 따라감) → templates 찾기 ---
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "${SOURCE#/}" = "$SOURCE" ] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
TPL="$SCRIPT_DIR/templates"
[ -d "$TPL" ] || die "templates 폴더를 찾을 수 없습니다: $TPL"

# --- 대상 디렉토리 (인자 없으면 현재 폴더) ---
TARGET="${1:-$PWD}"
[ -d "$TARGET" ] || die "대상 폴더가 없습니다: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
VSC="$TARGET/.vscode"
mkdir -p "$VSC"

# --- main.cpp / user.cpp 안내 (없어도 생성은 진행) ---
[ -f "$TARGET/main.cpp" ] || warn "main.cpp 가 없습니다 (빌드 시 필요)."
[ -f "$TARGET/user.cpp" ] || warn "user.cpp 가 없습니다 (빌드 시 필요)."

# --- 템플릿 복사 (기존 파일은 .bak 백업 후 덮어씀) ---
for f in tasks.json launch.json; do
    if [ -f "$VSC/$f" ]; then
        cp "$VSC/$f" "$VSC/$f.bak"
        warn "$f 이미 존재 → $f.bak 으로 백업"
    fi
    cp "$TPL/$f" "$VSC/$f"
    log "생성: .vscode/$f"
done

echo
log "✅ 완료: $VSC"
echo "   • Ctrl+Shift+B : build release (-O2, 기본)"
echo "   • F5           : build debug (-g) 후 디버깅"
echo "   • 터미널 태스크: build/run exam(-O0, 타임측정), release, debug"
echo "   • (디버깅엔 ms-vscode.cpptools 확장 필요 — install.sh 가 설치)"
