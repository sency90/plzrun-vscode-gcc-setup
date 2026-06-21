#!/usr/bin/env bash
# ============================================================================
#  plzrun-vscode-gcc-setup installer
#  - 전역 명령 `plzrun-vscode-gcc-setup` 설치 (~/.local/bin)
#  - VSCode 디버깅용 확장 ms-vscode.cpptools 자동 설치
#  가정: VSCode + `code` CLI 사용 가능 (Windows 는 Remote-WSL 안에서 실행)
#  사용법:  bash install.sh
# ============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;32m[vsc-gcc]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vsc-gcc:warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[vsc-gcc:err]\033[0m %s\n' "$*" >&2; exit 1; }

CMD_NAME="plzrun-vscode-gcc-setup"
SHARE_DIR="$HOME/.local/share/$CMD_NAME"
BIN="$HOME/.local/bin/$CMD_NAME"
CPP_EXT="ms-vscode.cpptools"

# --- 0. 요구사항 점검 (빌드 자체는 프로젝트에서 g++ 가 함 / 여기선 안내만) ---
command -v g++ >/dev/null 2>&1 || warn "g++ 가 안 보입니다. 빌드(Ctrl+Shift+B/F5) 시 g++ 필요."
case "$(uname -s)" in
    Linux) command -v gdb >/dev/null 2>&1 || warn "gdb 가 없습니다 → F5 디버깅 불가(빌드/실행은 OK). 필요시 gdb 설치." ;;
    Darwin) command -v lldb >/dev/null 2>&1 || warn "lldb 가 없습니다 → F5 디버깅 불가. Xcode Command Line Tools 설치 필요." ;;
esac

# --- 1. 생성기 + 템플릿을 share 에 복사 (repo 위치와 독립) ---
mkdir -p "$SHARE_DIR"
cp "$SCRIPT_DIR/setup.sh" "$SHARE_DIR/setup.sh"
rm -rf "$SHARE_DIR/templates"
cp -R "$SCRIPT_DIR/templates" "$SHARE_DIR/templates"
chmod +x "$SHARE_DIR/setup.sh"
log "생성기 설치: $SHARE_DIR"

# --- 2. ~/.local/bin 에 명령 설치 (share/setup.sh 로 위임) ---
mkdir -p "$HOME/.local/bin"
cat > "$BIN" <<EOF
#!/usr/bin/env bash
exec bash "$SHARE_DIR/setup.sh" "\$@"
EOF
chmod +x "$BIN"
log "명령 설치: $BIN"

# --- 3. VSCode cpptools 확장 설치 (디버깅용) ---
if command -v code >/dev/null 2>&1; then
    if code --install-extension "$CPP_EXT" --force >/dev/null 2>&1; then
        log "VSCode 확장 설치: $CPP_EXT"
    else
        warn "확장 자동설치 실패 — VSCode에서 '$CPP_EXT' 직접 설치하세요."
    fi
else
    warn "'code' CLI 없음 → 확장 '$CPP_EXT' 수동 설치 필요 (디버깅용)."
fi

# --- 4. PATH 안내 ---
case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) warn "~/.local/bin 이 PATH에 없습니다. 셸 설정에 추가하세요:"
       warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc  (zsh면 ~/.zshrc)" ;;
esac

echo
log "✅ 설치 완료!"
echo "   • 사용: 프로젝트 폴더에서  $CMD_NAME   →  ./.vscode 생성"
echo "   • 제거: bash uninstall.sh"
