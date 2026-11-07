#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup uninstaller
#  - 전역 명령 두 개(vsc, plzrun-vscode-gcc-setup) + 생성기 복사본 제거
#    (이 도구가 만든 래퍼만 지운다. 같은 이름의 다른 프로그램은 두고 알린다)
#  - cpptools 확장은 범용 확장이라 제거하지 않음(원하면 수동)
#  - 사용자 keybindings.json 의 Shift+Esc 칸(vsc 가 넣은 부분)만 뺀다. 칸을 빼는 곳은
#    여기와 vsc -shift-esc off 뿐이다(폴더별 vsc --remove 는 칸을 건드리지 않는다)
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
# Shift+Esc: 사용자 keybindings.json 의 vsc 칸을 통째로 뺀다(사용자 항목은 그대로)
KB_LIB="$SHARE_DIR/lib/keybindings.sh"
[ -f "$KB_LIB" ] || KB_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/keybindings.sh"
if [ -f "$KB_LIB" ]; then
    . "$KB_LIB"
    kb_path; kb="$KB_PATH"
    if [ -z "$kb" ]; then log "Shift+Esc: nothing to remove (${KB_WHY})"
    else
        kb_update "$kb" /dev/null off
        case "$KB_STATUS" in
            cleared) log "removed the Shift+Esc part from $kb (your own keybindings are kept)" ;;
            refused) warn "could not remove the Shift+Esc part from $kb: $KB_WHY (file not changed)" ;;
            *)       log "Shift+Esc: no vsc part in $kb (skipped)" ;;
        esac
    fi
fi
if [ -d "$SHARE_DIR" ]; then rm -rf "$SHARE_DIR"; log "removed: $SHARE_DIR"; else log "no generator copy (skipped)"; fi
rmdir "$BIN_DIR" 2>/dev/null && log "removed the empty ~/.local/bin" || true

echo
log "done."
log "note: the VSCode extension 'ms-vscode.cpptools' is kept (it is general). To remove it: code --uninstall-extension ms-vscode.cpptools"
log "note: .vscode/ in each project is kept. To remove it, run 'vsc --remove' in that folder before uninstalling."
