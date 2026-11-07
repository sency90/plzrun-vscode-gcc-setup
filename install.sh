#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup installer
#  - 전역 명령 설치 (~/.local/bin): 짧은 이름 vsc + 옛 이름 plzrun-vscode-gcc-setup
#    (둘 다 같은 setup.sh 를 부른다)
#  - VSCode 디버깅용 확장 ms-vscode.cpptools 자동 설치
#  - Shift+Esc = Esc 를 PC 전체로 켠다(사용자 keybindings.json 에 vsc 칸, 다시 돌려도 하나).
#    끄기는 vsc -shift-esc off 또는 uninstall.sh. 폴더별 vsc 명령은 이 칸을 건드리지 않는다
#  - C/C++ 코드 조각 제안(cpptools 의 if, for, class 틀)을 끈다("C_Cpp.suggestSnippets": false 를
#    VSCode settings.json 의 vsc 칸에, WSL 은 Remote-WSL 원격 설정에). 되돌리기는 vsc -cpp-snippets on
#    또는 uninstall.sh. 변수, 함수, 멤버 이름 제안과 다른 언어는 그대로
#  가정: VSCode + `code` CLI 사용 가능 (Windows 는 Remote-WSL 안에서 실행)
#  사용법:  bash install.sh
#  출력은 영어 (한글이 깨지는 터미널 대비)
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '[vsc-install] %s\n' "$*"; }
warn() { printf '[vsc-install] warning: %s\n' "$*"; }

CMD_NAME="plzrun-vscode-gcc-setup"
SHORT_NAME="vsc"
MARK="plzrun-vscode-gcc-setup"   # 옛 래퍼(share 경로만 있음)도 우리 것으로 본다
SHARE_DIR="$HOME/.local/share/$CMD_NAME"
BIN_DIR="$HOME/.local/bin"
CPP_EXT="ms-vscode.cpptools"

# --- 0. 요구사항 점검 (빌드 자체는 프로젝트에서 g++ 가 함 / 여기선 안내만) ---
command -v g++ >/dev/null 2>&1 || warn "g++ not found. Builds (Ctrl+Shift+B, F5) need g++."
case "$(uname -s)" in
    Linux) command -v gdb >/dev/null 2>&1 || warn "gdb not found: F5 debugging will not work (build and run are fine). Install gdb if needed." ;;
    Darwin) command -v lldb >/dev/null 2>&1 || warn "lldb not found: F5 debugging will not work. Install the Xcode Command Line Tools." ;;
esac

# --- 1. 생성기 + 템플릿을 share 에 복사 (repo 위치와 독립) ---
mkdir -p "$SHARE_DIR"
cp "$SCRIPT_DIR/setup.sh" "$SHARE_DIR/setup.sh"
rm -rf "$SHARE_DIR/templates" "$SHARE_DIR/lib"
cp -R "$SCRIPT_DIR/templates" "$SHARE_DIR/templates"
cp -R "$SCRIPT_DIR/lib" "$SHARE_DIR/lib"
chmod +x "$SHARE_DIR/setup.sh"
log "installed the generator: $SHARE_DIR"

# --- 2. ~/.local/bin 에 명령 두 개 설치 (share/setup.sh 로 위임) ---
#   이 도구가 만들지 않은 같은 이름 파일이 있으면 덮지 않는다
mkdir -p "$BIN_DIR"
install_cmd() {
    local bin="$BIN_DIR/$1"
    if [ -e "$bin" ] && ! grep -q "$MARK" "$bin" 2>/dev/null; then
        warn "$bin already exists and is not ours; left it alone (use the other name, or remove it and run install.sh again)"
        return 0
    fi
    cat > "$bin" <<WRAP
#!/usr/bin/env bash
# $MARK wrapper (install.sh)
exec bash "$SHARE_DIR/setup.sh" "\$@"
WRAP
    chmod +x "$bin"
    log "installed the command: $bin"
}
install_cmd "$CMD_NAME"
install_cmd "$SHORT_NAME"

# 다른 vsc 가 PATH 앞쪽에 있으면 알린다
found="$(command -v "$SHORT_NAME" 2>/dev/null || true)"
if [ -n "$found" ] && [ "$found" != "$BIN_DIR/$SHORT_NAME" ]; then
    warn "another '$SHORT_NAME' comes first in PATH: $found"
    warn "  '$SHORT_NAME' will run that one; '$CMD_NAME' still runs this tool"
fi

# --- 3. VSCode cpptools 확장 설치 (디버깅용) ---
if command -v code >/dev/null 2>&1; then
    if code --install-extension "$CPP_EXT" --force >/dev/null 2>&1; then
        log "installed the VSCode extension: $CPP_EXT"
    else
        warn "could not install the extension; install '$CPP_EXT' in VSCode yourself."
    fi
else
    warn "'code' CLI not found; install the extension '$CPP_EXT' yourself (needed for F5)."
fi

# --- 4. Shift+Esc = Esc (PC 전체, 사용자 keybindings.json 의 vsc 칸) ---
#   v1.3.0 이 넣은 폴더 한정 칸이 있으면 PC 전체 칸으로 바꾼다. 사용자 항목은 그대로
. "$SHARE_DIR/lib/keybindings.sh"
kb_path; kb="$KB_PATH"
if [ -z "$kb" ]; then
    warn "Shift+Esc was not set up (${KB_WHY}); add the keybindings in that VSCode yourself if you need them"
    warn "  the list: $SHARE_DIR/templates/shift-esc.tsv"
else
    kb_update "$kb" "$SHARE_DIR/templates/shift-esc.tsv" on
    case "$KB_STATUS" in
        added)     log "Shift+Esc now works like Esc everywhere in VSCode (added the vsc part to $kb)" ;;
        updated)   if [ -n "$KB_FOLDERS" ]; then
                       log "Shift+Esc now works like Esc everywhere in VSCode (the old part was limited to some folders; rewrote it in $kb)"
                   else
                       log "Shift+Esc: rewrote the vsc part in $kb with this version's keybindings"
                   fi ;;
        unchanged) log "Shift+Esc already works like Esc everywhere in VSCode ($kb not changed)" ;;
        refused)   warn "Shift+Esc was not set up: $KB_WHY ($kb was not changed)" ;;
    esac
fi

# --- 5. C/C++ 코드 조각 제안 끄기 (settings.json 의 vsc 칸, lib/settings.sh) ---
#   중괄호를 치다 "if (condition) { /* code */ }" 가 끼어드는 것을 막는다(task465)
. "$SHARE_DIR/lib/settings.sh"
st_path; st="$ST_PATH"
if [ -z "$st" ]; then
    warn "C/C++ code snippets were not turned off (${ST_WHY}); set \"$ST_KEY\": false in that VSCode yourself"
else
    where=""; [ "$ST_REMOTE" -eq 1 ] && where=" (the Remote-WSL settings of this Linux; the Windows side is not changed)"
    st_update "$st" off
    case "$ST_STATUS" in
        added)     log "C/C++ code snippets (if, for, class ...) are off: VSCode no longer offers them while you type (added the vsc part to $st)$where" ;;
        updated)   log "C/C++ code snippets (if, for, class ...) are off (rewrote the vsc part in $st)$where" ;;
        unchanged) log "C/C++ code snippets (if, for, class ...) are off already ($st not changed)" ;;
        refused)   warn "C/C++ code snippets were not turned off: $ST_WHY ($st was not changed)" ;;
    esac
    case "$ST_STATUS" in
        added|updated|unchanged)
            log "  names of variables, functions and members are still suggested; other languages are not changed"
            if [ "$ST_OWN" -eq 1 ]; then warn "your own \"$ST_KEY\" in $st comes later and wins over the vsc part"; fi ;;
    esac
fi

# --- 6. PATH 안내 ---
case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) warn "~/.local/bin is not in PATH. Add it to your shell settings:"
       warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc   (zsh: ~/.zshrc)" ;;
esac

echo
log "done."
echo "   use:       in a problem folder, run  $SHORT_NAME   (same as $CMD_NAME)"
echo "   help:      $SHORT_NAME --help"
echo "   Shift+Esc: $SHORT_NAME -shift-esc off   turns Shift+Esc = Esc off ($SHORT_NAME -shift-esc on turns it back on)"
echo "   snippets:  $SHORT_NAME -cpp-snippets on   brings the C/C++ code snippets back ($SHORT_NAME -cpp-snippets off turns them off)"
echo "   uninstall: bash uninstall.sh"
