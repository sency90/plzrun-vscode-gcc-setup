#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup uninstaller
#  - 전역 명령 + 생성기 복사본 제거
#  - cpptools 확장은 범용 확장이라 제거하지 않음(원하면 수동)
#  - 이미 각 프로젝트에 생성된 .vscode 는 사용자 자산이라 건드리지 않음
# ============================================================================
set -uo pipefail

log()  { printf '\033[1;32m[vsc-gcc]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vsc-gcc:warn]\033[0m %s\n' "$*"; }

CMD_NAME="plzrun-vscode-gcc-setup"
SHARE_DIR="$HOME/.local/share/$CMD_NAME"
BIN="$HOME/.local/bin/$CMD_NAME"

if [ -f "$BIN" ]; then rm -f "$BIN"; log "제거: $BIN"; else log "명령 없음 (건너뜀)"; fi
if [ -d "$SHARE_DIR" ]; then rm -rf "$SHARE_DIR"; log "제거: $SHARE_DIR"; else log "생성기 복사본 없음 (건너뜀)"; fi
rmdir "$HOME/.local/bin" 2>/dev/null && log "빈 ~/.local/bin 제거" || true

echo
log "✅ 제거 완료."
warn "참고: VSCode 확장 'ms-vscode.cpptools' 는 그대로 둡니다(범용). 제거하려면: code --uninstall-extension ms-vscode.cpptools"
warn "참고: 각 프로젝트의 .vscode/ 는 그대로 둡니다(사용자 자산)."
