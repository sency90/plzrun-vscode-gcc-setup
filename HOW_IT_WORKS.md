# plzrun-vscode-gcc-setup — 어떻게 만들었나 (개발 노트)

sw_expert(C/C++) 프로젝트의 **VSCode 컴파일/디버그 설정(`.vscode/`)을 한 명령으로 생성**하는 도구. 이 문서는 무엇을/왜/어떻게 만들었는지 설명한다.

---

## 0. 목적
새 sw_expert 문제 폴더(= `main.cpp` + `user.cpp`)에서 명령 한 줄이면 `.vscode/`가 생겨서, 바로 빌드(`Ctrl+Shift+B`)·디버그(`F5`)·실행이 되게 하는 것. 매번 다른 프로젝트에서 `.vscode` 복사해와서 고치던 걸 자동화.

---

## 1. 핵심 전제 — "Windows도 결국 Linux"
- 동혁님은 **Windows에선 VSCode를 Remote-WSL(Ubuntu)로** 폴더를 연다. 즉 빌드/디버그가 **WSL(리눅스) 안에서** 돈다.
- macOS도 native.
- → **두 환경 다 POSIX `g++`** 이라, 예전처럼 `wsl.exe`로 분기할 필요가 없다. tasks가 단순해짐(그냥 `g++`).

---

## 2. 생성되는 `.vscode/` 두 파일

### `tasks.json` — 빌드 3종 (`templates/tasks.json`)
| 용도 | 컴파일 | 산출물 |
|---|---|---|
| **exam** | `g++ -std=c++14 -O0 main.cpp ${file} -o pgm_exam` | 시험 옵션, 타임 측정(`time ./pgm_exam`) |
| **release** | `g++ -std=c++14 -O2 ... -o pgm_release` | 빠른 실행 (`Ctrl+Shift+B` 기본) |
| **debug** | `g++ -std=c++14 -g ... -o pgm_debug` | `F5` 디버깅용 |

- **`${file}`** = "지금 편집기에서 포커스한 파일". VSCode가 빌드 시 실제 파일 경로로 치환해준다. 그래서 `user.cpp` 고정이 아니라, 보고 있는 풀이 파일(`score_455_mojo.cpp` 등)이 컴파일된다. `main.cpp`은 항상 들어가고 불변.
- `*.cpp` 전체가 아니라 **`main.cpp` + `${file}` 둘만** 컴파일 → 같은 폴더의 다른 풀이 .cpp끼리 심볼 충돌 방지.
- 왜 `c++14`인가: sw_expert `main.cpp`가 `register` 키워드를 쓰는데, **C++17은 `register`가 제거돼 에러**. 그래서 c++14 고정.

### `launch.json` — F5 디버깅 (`templates/launch.json`)
- `F5` → `preLaunchTask`로 debug 빌드 후 `pgm_debug` 디버깅.
- **디버거 OS 자동 분기**: VSCode launch.json은 `"linux"`/`"osx"` 같은 OS별 override 키를 지원한다.
  - Linux/WSL → `gdb` (`/usr/bin/gdb`)
  - macOS → `lldb`
  - 한 파일이 양쪽 다 커버.
- `cppdbg` 타입은 **`ms-vscode.cpptools` 확장**이 있어야 동작 → install.sh가 자동 설치.

> "tasks/launch가 뭐냐": VSCode가 정한 표준 설정 파일. tasks.json = "이런 빌드/실행 명령들을 단축키/메뉴로 제공해라". launch.json = "F5 누르면 이렇게 디버깅 시작해라". 둘 다 그냥 JSON 텍스트라 사람이 읽고 고칠 수 있다.

---

## 3. 생성기 구조

```
setup.sh        ← 실제 생성기. 현재 폴더(또는 인자 폴더)에 .vscode/ 생성
templates/      ← 부어 넣을 tasks.json / launch.json 원본
install.sh      ← 전역 명령 'plzrun-vscode-gcc-setup' 설치 + cpptools 확장
uninstall.sh    ← 명령/복사본 제거
```

### `setup.sh` 가 하는 일
1. **자기 위치를 심링크까지 따라가 해석**해서 `templates/`를 찾는다(설치 후 `~/.local/bin`의 명령이 심링크/래퍼여도 원본 templates를 찾도록).
2. 대상 폴더에 `.vscode/` 만들고, 기존 `tasks.json`/`launch.json`이 있으면 `.bak`로 백업 후 템플릿 복사.
3. `main.cpp`/`user.cpp` 없으면 경고만(생성은 진행).
   - 템플릿은 변수 치환이 거의 없어서 **그냥 복사**면 됨 → python도 필요 없이 `cp`로 끝.

### `install.sh` 가 하는 일
1. `g++`/`gdb`(Linux)/`lldb`(mac) 존재를 점검(없으면 빌드/디버그 시 곤란하다고 경고).
2. 생성기(setup.sh + templates)를 `~/.local/share/plzrun-vscode-gcc-setup/`에 복사.
3. `~/.local/bin/plzrun-vscode-gcc-setup` 래퍼 생성 → 위 setup.sh를 현재 폴더에서 실행.
4. `ms-vscode.cpptools` 확장 설치(`code --install-extension`).
5. `~/.local/bin`이 PATH에 없으면 추가 방법 안내.

### `uninstall.sh`
- `~/.local/bin`의 명령 + `~/.local/share/...` 복사본 제거.
- **cpptools는 범용 확장이라 제거하지 않음**(다른 C++ 작업에 쓰일 수 있으니). 이미 생성된 각 프로젝트의 `.vscode/`도 사용자 자산이라 그대로 둠.

---

## 4. 사용 흐름
```bash
# 최초 1회 (PC당)
cd ~/github/plzrun-vscode-gcc-setup && bash install.sh

# 그 다음부터, 새 문제 폴더에서 한 줄
plzrun-vscode-gcc-setup        # → ./.vscode 생성
```
그 폴더를 VSCode로 열고(회사면 Remote-WSL): `Ctrl+Shift+B`(release 빌드) / `F5`(debug 디버깅) / 터미널 태스크로 `run exam (timed)` 등.

---

## 5. 의존성 / 라이선스
- 의존: `bash`, `g++`(C++14), `code` CLI, (디버깅 시)`gdb`/`lldb`, (확장)`ms-vscode.cpptools`.
- 패키지매니저/네트워크 불필요(생성기는 파일 복사뿐).
- 라이선스: MIT.

---

## 6. 자매 도구
- **포맷 자동정렬**은 별도 repo `plzrun-auto-indent`(astyle + vim/VSCode 연동). 이 repo는 **컴파일/디버그 세팅 생성**만 담당. 둘은 독립.
