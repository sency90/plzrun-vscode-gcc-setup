#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup uninstaller
#  - 전역 명령 두 개(vsc, plzrun-vscode-gcc-setup) + 생성기 복사본 제거
#    (이 도구가 만든 래퍼만 지운다. 같은 이름의 다른 프로그램은 두고 알린다)
#  - cpptools 확장은 범용 확장이라 제거하지 않음(원하면 수동)
#  - 이미 각 프로젝트에 생성된 .vscode 는 사용자 자산이라 건드리지 않음
#    (프로젝트마다 지우려면 그 폴더에서 vsc --remove)
# ============================================================================
set -uo pipefail

log()  { printf '[vsc-uninstall] %s\n' "$*"; }
warn() { printf '[vsc-uninstall] warning: %s\n' "$*"; }

CMD_NAME="plzrun-vscode-gcc-setup"
MARK="$CMD_NAME"
SHARE_DIR="$HOME/.local/share/$CMD_NAME"
BIN_DIR="$HOME/.local/bin"

for name in vsc "$CMD_NAME"; do
    bin="$BIN_DIR/$name"
    if [ ! -e "$bin" ]; then log "no command $bin (skipped)"; continue; fi
    if grep -q "$MARK" "$bin" 2>/dev/null; then rm -f "$bin"; log "removed: $bin"
    else warn "$bin is not ours; left it alone"; fi
done
if [ -d "$SHARE_DIR" ]; then rm -rf "$SHARE_DIR"; log "removed: $SHARE_DIR"; else log "no generator copy (skipped)"; fi
rmdir "$BIN_DIR" 2>/dev/null && log "removed the empty ~/.local/bin" || true

echo
log "done."
log "note: the VSCode extension 'ms-vscode.cpptools' is kept (it is general). To remove it: code --uninstall-extension ms-vscode.cpptools"
log "note: .vscode/ in each project is kept. To remove it, run 'vsc --remove' in that folder before uninstalling."
