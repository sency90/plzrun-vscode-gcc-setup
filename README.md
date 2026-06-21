# plzrun-vscode-gcc-setup

sw_expert(C/C++) 프로젝트의 **VSCode 컴파일 세팅(`.vscode/`)을 한 번에 생성**하는 도구.
빌드 명령 한 줄도 외부 의존성 없이 `g++` 만 쓰며, **Windows 는 Remote-WSL(Ubuntu) 안에서 실행**하는 것을 전제로 한다 (macOS native 도 동일하게 동작).

## 설치 / 제거

```bash
cd ~/github/plzrun-vscode-gcc-setup
bash install.sh      # 전역 명령 설치 + cpptools 확장 설치
bash uninstall.sh    # 전역 명령 제거
```

## 사용

새 sw_expert 프로젝트 폴더(= `main.cpp`, `user.cpp` 가 있는 곳)에서:

```bash
plzrun-vscode-gcc-setup       # 현재 폴더에 ./.vscode/ 생성
```
> 설치 없이 바로 쓰려면: `bash ~/github/plzrun-vscode-gcc-setup/setup.sh [대상폴더]`

## 생성되는 빌드 구성 (`.vscode/tasks.json`)

| 용도 | 명령 | 산출물 |
|---|---|---|
| **exam** (시험 옵션, 타임 측정) | `g++ -std=c++14 -O0 main.cpp user.cpp -o pgm_exam` | `pgm_exam` |
| **release** (빠른 실행 확인) | `g++ -std=c++14 -O2 main.cpp user.cpp -o pgm_release` | `pgm_release` |
| **debug** (F5 디버깅) | `g++ -std=c++14 -g main.cpp user.cpp -o pgm_debug` | `pgm_debug` |

- `Ctrl+Shift+B` → **build release** (기본)
- 터미널 태스크: `run exam (timed)` = `time ./pgm_exam`, `run release` 등
- 컴파일 대상은 **`main.cpp` + `user.cpp` 만** (같은 폴더의 다른 `.cpp` 와 충돌 방지)

## 디버깅 (`.vscode/launch.json`)

- **F5** → `build debug` 후 `pgm_debug` 디버깅
- 디버거 **OS 자동 분기**: Linux/WSL = `gdb` (`/usr/bin/gdb`), macOS = `lldb`
- 필요 확장: `ms-vscode.cpptools` (install.sh 가 자동 설치)
- ⚠️ Linux/WSL 에서 F5 디버깅하려면 `gdb` 가 설치돼 있어야 함 (빌드/실행은 불필요)

## 가정 / 의존성

- VSCode + `code` CLI 사용 가능 (Windows 는 Remote-WSL)
- 빌드 시 `g++` (C++14)
- 패키지매니저·네트워크 불필요 (생성기 자체는 파일 복사만)

## 구성

```
plzrun-vscode-gcc-setup/
├── install.sh / uninstall.sh
├── setup.sh                 # 실제 생성기 (CWD/.vscode 생성)
├── templates/
│   ├── tasks.json
│   └── launch.json
├── LICENSE                  # MIT
└── README.md
```

## 라이선스

MIT (루트 `LICENSE`).
