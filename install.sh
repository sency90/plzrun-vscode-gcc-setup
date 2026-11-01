#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup installer
#  - 전역 명령 설치 (~/.local/bin): 짧은 이름 vsc + 옛 이름 plzrun-vscode-gcc-setup
#    (둘 다 같은 setup.sh 를 부른다)
#  - VSCode 디버깅용 확장 ms-vscode.cpptools 자동 설치
#  - Shift+Esc = Esc 는 여기서 넣지 않는다. 폴더마다 vsc 를 칠 때 그 폴더용으로 넣는다
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

# --- 4. PATH 안내 ---
case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) warn "~/.local/bin is not in PATH. Add it to your shell settings:"
       warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc   (zsh: ~/.zshrc)" ;;
esac

echo
log "done."
echo "   use:       in a problem folder, run  $SHORT_NAME   (same as $CMD_NAME)"
echo "   help:      $SHORT_NAME --help"
echo "   uninstall: bash uninstall.sh"
