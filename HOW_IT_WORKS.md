# plzrun-vscode-gcc-setup — 어떻게 만들었나 (개발 노트)

sw_expert(C/C++) 프로젝트의 **VSCode 컴파일/디버그 설정(`.vscode/`)을 한 명령으로 생성**하는 도구. 이 문서는 무엇을/왜/어떻게 만들었는지 설명한다.

---

## 0. 목적
새 문제 폴더에서 명령 한 줄(`vsc`)이면 `.vscode/`가 생겨서, 바로 빌드(`Ctrl+Shift+B`), 디버그(`F5`), 실행이 되게 하는 것. 매번 다른 프로젝트에서 `.vscode` 복사해와서 고치던 걸 자동화.

- 처음엔 sw_expert 폴더(`main.cpp` + `user.cpp`, ex 방식)만 가정했다.
- 2026-11 에 BOJ/poj 처럼 파일 하나로 푸는 폴더(single 방식)와, 세팅 뒤 같은 명령으로 언어와 입출력을 바꾸는 기능을 더했다.

---

## 1. 핵심 전제 — "Windows도 결국 Linux"
- 동혁님은 **Windows에선 VSCode를 Remote-WSL(Ubuntu)로** 폴더를 연다. 즉 빌드/디버그가 **WSL(리눅스) 안에서** 돈다.
- macOS도 native.
- → **두 환경 다 POSIX `g++`** 이라, 예전처럼 `wsl.exe`로 분기할 필요가 없다. tasks가 단순해짐(그냥 `g++`).

---

## 2. 생성되는 `.vscode/` 파일

- `vsc.conf`: 설정 원본(mode, lang, stdin, stdout 네 줄).
- `tasks.json`, `launch.json`: `vsc.conf` 값으로 `templates/` 를 채워 매번 다시 만든다.
- `vsc-f5-stdin`: F5 직전에 입력 파일을 복사해 두는 곳(아래 launch.json 참고).

아래 표는 ex 방식 기준이다. single 방식은 `main.cpp` 없이 `${file}` 하나를 빌드하고, 실행 파일을 그 파일 옆에 파일 이름대로 만든다(`${fileDirname}/${fileBasenameNoExtension}`). 빌드는 release(-O2), debug(-g) 둘.

### `tasks.json` — 빌드 3종 (`templates/tasks.json`)
| 용도 | 컴파일 | 산출물 |
|---|---|---|
| **exam** | `g++ -std=c++14 -O0 main.cpp ${file} -o pgm_exam` | 시험 옵션, 타임 측정(`time ./pgm_exam`) |
| **release** | `g++ -std=c++14 -O2 ... -o pgm_release` | 빠른 실행 (`Ctrl+Shift+B` 기본) |
| **debug** | `g++ -std=c++14 -g ... -o pgm_debug` | `F5` 디버깅용 |

- **`${file}`** = "지금 편집기에서 포커스한 파일". VSCode가 빌드 시 실제 파일 경로로 치환해준다. 그래서 `user.cpp` 고정이 아니라, 보고 있는 풀이 파일(`score_455_mojo.cpp` 등)이 컴파일된다. `main.cpp`은 항상 들어가고 불변.
- `*.cpp` 전체가 아니라 **`main.cpp` + `${file}` 둘만** 컴파일 → 같은 폴더의 다른 풀이 .cpp끼리 심볼 충돌 방지.
- 왜 기본이 `c++14`인가: sw_expert `main.cpp`가 `register` 키워드를 쓰는데, **C++17은 `register`가 제거돼 에러**. 그래서 기본은 c++14 이고, `vsc -lang c++17` 로 바꿀 수 있다.
- run 태스크는 `/bin/bash -c` 로 돈다. 입력 파일이 있으면 `< in`, 없으면 리다이렉트 없이 돌리고 경고 한 줄. 사용자 기본 셸(zsh, fish)과 상관없이 같은 문법이 통하게 하려고 셸을 정해 둔다.

### `launch.json` — F5 디버깅 (`templates/launch.json`)
- `F5` → `preLaunchTask`로 debug 빌드 후 `pgm_debug` 디버깅.
- **디버거 OS 자동 분기**: VSCode launch.json은 `"linux"`/`"osx"` 같은 OS별 override 키를 지원한다.
  - Linux/WSL → `gdb` (`/usr/bin/gdb`)
  - macOS → `lldb`
  - 한 파일이 양쪽 다 커버.
- `cppdbg` 타입은 **`ms-vscode.cpptools` 확장**이 있어야 동작 → install.sh가 자동 설치.
- **F5 입력 파일**: launch.json 은 "파일이 있을 때만 리다이렉트" 같은 조건을 못 쓴다. 그래서 preLaunchTask(`vsc: prepare F5`)가 입력 파일을 `.vscode/vsc-f5-stdin` 으로 복사하고(없으면 빈 파일 + 경고), 디버거는 늘 그 사본을 읽는다.
  - 모든 OS 공통 `"args": ["<", ".../vsc-f5-stdin"]` (출력 파일이 있으면 `">", ".../out2"` 도).
  - gdb F5: gdb 는 셸을 거쳐 프로그램을 띄우므로 리다이렉트가 먹는다.
  - lldb F5: 인자가 셸을 안 거쳐 `<` 가 그대로 argv 로 간다. 그래서 `setupCommands` 에 `settings set target.input-path` (출력은 `target.output-path`)를 더 넣는다. cpptools 는 `-` 로 시작하지 않는 setupCommands 를 `-interpreter-exec console` 로 보내고, 타깃을 만들기 전에 넣은 설정도 새 타깃에 이어진다(lldb-mi 로 직접 확인).
- **Ctrl+F5 (Run Without Debugging)**: cpptools 1.34.4 는 noDebug 실행을 디버거에 보내지 않는다. `dist/src/main.js` 의 `RunWithoutDebuggingAdapter` 가 터미널에서 `program args` 를 바로 실행한다.
  - 이 경로는 `program`, `args`, `cwd`, `environment`, `console`/`externalConsole` 만 읽는다. `setupCommands` 와 `MIMode` 는 쓰지 않는다.
  - 셸 통합이 있으면 VSCode `executeCommand(program, args)` 로, 없으면 `buildShellCommandLine` 으로 명령 줄을 만든다. 둘 다 빈칸 있는 인자만 따옴표로 감싸므로 `<`, `>` 는 셸이 리다이렉트로 받는다.
  - v1.2.0 은 macOS 입력을 `setupCommands` 에만 넣어서 Ctrl+F5 에서 입력 파일이 빠졌다(task369). 그래서 `args` 를 모든 OS 공통으로 옮겼다.
  - VSCode 는 `"osx"`/`"linux"` 블록의 키를 맨 위 키에 얕게 덮어쓴다. 블록에 `args` 를 두지 않아야 공통 `args` 가 남는다.

> "tasks/launch가 뭐냐": VSCode가 정한 표준 설정 파일. tasks.json = "이런 빌드/실행 명령들을 단축키/메뉴로 제공해라". launch.json = "F5 누르면 이렇게 디버깅 시작해라". 둘 다 그냥 JSON 텍스트라 사람이 읽고 고칠 수 있다.

---

## 3. 생성기 구조

```
setup.sh        ← 실제 생성기. 현재 폴더(또는 인자 폴더)에 .vscode/ 생성
templates/      ← 부어 넣을 tasks.json / launch.json 원본
lib/            ← vscpart.sh: VSCode 사용자 파일의 vsc 칸 넣기와 빼기
                   keybindings.sh: Shift+Esc 칸, settings.sh: C/C++ 코드 조각 끄기 칸
install.sh      ← 전역 명령 vsc, 'plzrun-vscode-gcc-setup' 설치 + cpptools 확장 + Shift+Esc 켜기 + 코드 조각 끄기 + EditContext 끄기
uninstall.sh    ← 명령, 복사본 제거 + Shift+Esc 끄기 + 코드 조각, EditContext 되돌리기
```

### `setup.sh` 가 하는 일
1. **자기 위치를 심링크까지 따라가 해석**해서 `templates/`를 찾는다(설치 후 `~/.local/bin`의 명령이 심링크/래퍼여도 원본 templates를 찾도록).
2. 인자를 읽는다. 값 있는 옵션은 대시 하나, 값 없는 옵션은 대시 둘. 모르는 옵션이나 값은 거리(글자 바꾸기, 넣기, 빼기, 이웃 두 글자 뒤바꾸기)가 가장 가까운 것을 `Did you mean` 으로 알려 주고 아무것도 바꾸지 않는다. 거리 계산은 `awk` 로 한다.
3. 대상 폴더를 정한다. 폴더를 안 주면 현재 폴더. 다만 현재 폴더에 `main.cpp` 도 `.vscode/` 도 없으면(poj/14216 같은 문제 폴더) 위로 올라가 `vsc.conf` 가 있는 폴더를 쓴다(git 이 `.git` 을 찾는 것과 같다).
   - `-shift-esc on|off`, `-cpp-snippets on|off`, `-edit-context on|off` 는 이 단계 전에 따로 처리한다. PC 전체 설정이라 폴더와 상관없고, 혼자 쓰면 여기서 끝난다.
4. `vsc.conf` 를 읽고(없으면 첫 세팅), `--init`, `--ex`, `--single`, `-lang`, `-stdin`, `-stdout` 순으로 새 값을 정한다.
5. `templates/` 의 `@STD@` 같은 자리를 채워 `tasks.json`, `launch.json` 을 만든다. 내용이 같으면 파일을 건드리지 않는다.
6. 이 도구가 만들지 않은 `tasks.json`, `launch.json` 이 있으면 `--force` 없이 덮지 않는다. 옛 버전처럼 `.bak` 를 만들지 않는다(사본이 쌓여 헷갈렸다).
7. 바뀐 값을 `old -> new` 로 출력한다. 출력은 전부 영어.
   - 치환은 `${var//a/b}` 대신 직접 짠 함수로 한다. bash 5.2 는 바꿀 말 안의 `&` 를 특별하게 다뤄서 `>&2` 같은 명령이 깨진다.
   - macOS 기본 bash 3.2 에서도 돌게 연관 배열, `${var,,}` 같은 새 문법을 쓰지 않는다.

### `install.sh` 가 하는 일
1. `g++`/`gdb`(Linux)/`lldb`(mac) 존재를 점검(없으면 빌드/디버그 시 곤란하다고 경고).
2. 생성기(setup.sh + templates)를 `~/.local/share/plzrun-vscode-gcc-setup/`에 복사.
3. `~/.local/bin/vsc` 와 `~/.local/bin/plzrun-vscode-gcc-setup` 래퍼 생성 → 둘 다 위 setup.sh를 현재 폴더에서 실행. 같은 이름의 다른 프로그램이 이미 있으면 덮지 않고 알린다.
4. `ms-vscode.cpptools` 확장 설치(`code --install-extension`).
5. Shift+Esc = Esc 를 켠다(사용자 `keybindings.json` 에 vsc 칸). 다시 돌려도 칸은 하나, v1.3.0 의 폴더 한정 칸은 PC 전체 칸으로 바꾼다.
6. C/C++ 코드 조각 제안을 끈다(VSCode `settings.json` 에 vsc 칸, `"C_Cpp.suggestSnippets": false`). WSL 은 Remote-WSL 원격 설정 `~/.vscode-server/data/Machine/settings.json` 에 넣는다.
7. EditContext 를 끈다(같은 `settings.json` 의 다른 vsc 칸, `"editor.editContext": false`). 한글 입력 때 커서 튐과 글자 중복을 막는다. WSL 도 같은 원격 설정.
8. `~/.local/bin`이 PATH에 없으면 추가 방법 안내.

### `uninstall.sh`
- `~/.local/bin`의 명령 두 개(이 도구 래퍼만) + `~/.local/share/...` 복사본 제거.
- 사용자 `keybindings.json` 의 Shift+Esc 칸을 뺀다(사용자 항목은 그대로).
- `settings.json` 의 C/C++ 코드 조각 칸과 EditContext 칸을 뺀다(사용자 설정은 그대로).
- **cpptools는 범용 확장이라 제거하지 않음**(다른 C++ 작업에 쓰일 수 있으니). 이미 생성된 각 프로젝트의 `.vscode/`도 사용자 자산이라 그대로 둠.

---

### Shift+Esc = Esc (`lib/keybindings.sh`, `templates/shift-esc.tsv`)
- 요청: Shift+Esc 를 자주 누르니 Esc 로 처리해 달라.
- 프로젝트 단위 단축키는 VSCode 에 없다. 1.143.1 본체 소스를 보면 단축키 서비스는 현재 프로필의 `keybindingsResource`(사용자 `keybindings.json`)만 읽는다.
  - 그래서 사용자 `keybindings.json` 에 넣는다. 이 파일은 PC 에 하나다.
- 처음(v1.3.0)에는 조건(`when`)에 `resourcePath =~ /^(폴더)\//` 를 더해 `vsc` 로 세팅한 폴더에서만 켰다. v1.4.0 에서 PC 전체 설정으로 바꿨다.
  - 이유: 프로젝트 10개에 세팅하고 하나를 지우면 나머지 9개에서는 계속 Shift+Esc = Esc 여야 한다. 폴더 목록을 맞추는 일이 프로젝트 명령에 묶이면 이런 때 헷갈린다.
  - 그래서 칸은 `install.sh` 가 켜고 `uninstall.sh` 가 끈다. 중간에 바꾸려면 `vsc -shift-esc on|off`. 프로젝트 명령(`vsc`, `--init`, `--remove`)은 칸을 건드리지 않는다.
  - 값이 붙는 옵션이라 대시 하나다(`-lang` 과 같은 규칙). `--shift-esc` 는 `--lang` 처럼 "대시 하나" 안내로 거절한다.
- Esc 의 일은 명령 하나가 아니다. Esc 에 묶인 기본 단축키가 81개(VSCode 1.143.1)이고, 그중 같은 일을 하는 Shift+Esc 단축키가 이미 있는 것은 18개뿐이다.
  - 이미 Shift+Esc 에 묶인 18개는 모두 Esc 와 같은 명령, 같은 조건이다. 다른 일을 하는 Shift+Esc 기본 단축키는 없다(충돌 없음).
  - 그래서 Esc 단축키 전부를 같은 차례로 복사한다. 사용자 파일의 규칙은 기본보다 우선하고, 한 파일 안에서는 뒤가 이긴다.
  - 그러므로 어디서나 Esc 에서 이기는 규칙의 복사본이 Shift+Esc 에서도 이긴다.
- VSCodeVim 의 Esc 는 `extension.vim_escape` 명령이고, 이 명령은 Vim 에 `<Esc>` 키를 그대로 넘긴다(확장 소스 확인). 그래서 Vim 입력 모드 빠져나가기도 같다.
  - Vim 설정(`vim.insertModeKeyBindings` 의 `<S-Esc>`)으로는 안 된다. VSCodeVim 은 자기 package.json 에 적힌 키만 받는데, Shift+Esc 는 거기 없다.
- 목록은 기본 단축키 JSON 덤프(VSCode 의 "Open Default Keyboard Shortcuts (JSON)" 과 같은 파일을 VSCode 판마다 저장한 공개 저장소)와 확장 package.json 에서 `tools/gen-shift-esc.py` 가 만든다. VSCode 판이 바뀌면 다시 만든다.
- 파일 고치기는 bash 와 awk 만 쓴다. 주석과 문자열을 건너뛰며 배열의 `[` 를 찾고 그 뒤에 칸을 넣는다.
  - 칸 밖 글자는 그대로다. `[` 줄 뒤에 글이 이어지면 줄을 나누고 표시(`[split]`)를 남겨, 뺄 때 다시 붙인다. 끝 줄바꿈이 없던 파일은 없는 채로 둔다.

### C/C++ 코드 조각 끄기 (`lib/settings.sh`, task465)
- 요청: 중괄호를 치다 `if (condition) { /* code */ }` 가 자주 끼어든다. 그것만 막고 다른 자동 완성은 그대로.
- 출처: cpptools 1.35.6 의 언어 서버 실행 파일 `bin/cpptools` 안에 코드 조각 표가 들어 있다(`strings` 로 확인).
  - "if statement" 의 본문은 `if (${1:condition})`, `{`, `${0:/* code */}`, `}` 네 줄이다. 목록에 보이는 이름은 "if" 다.
  - 같은 표에 21개가 있다. VSCode 1.144 내장 cpp 확장의 스니펫 파일에는 `#region`, `#endregion` 만 있다.
- 받아들이는 키(VSCode 1.144 본체 확인)
  - `acceptSelectedSuggestion` 은 목록이 열려 있을 때 Tab(늘), Enter(`editor.acceptSuggestionOnEnter` 기본 "on")에 묶여 있다.
  - 목록은 글자를 치면 저절로 열린다(`editor.quickSuggestions` 기본). cpptools 가 목록을 여는 글자는 `. " < > : / \ @` 뿐이고 `{`, `}` 는 아니다(언어 서버에 initialize 를 보내 받은 값).
  - 그래서 `{}` 바로 뒤에 글자를 치다 "if" 가 고른 항목인 채 Enter 나 Tab 이 눌리면, 친 글자가 지워지고 그 자리에 조각이 들어간다.
- 고른 설정: `"C_Cpp.suggestSnippets": false`. cpptools 확장이 언어 서버에 넘기는 값이고, 언어 서버가 코드 조각을 목록에 넣지 않는다.
  - 다른 후보와 같이 꺼지는 것
    - `"[cpp]": {"editor.snippetSuggestions": "none"}`: 사용자 스니펫, `#region` 까지 꺼진다.
    - `editor.acceptSuggestionOnEnter: "off"`: 모든 언어의 모든 제안을 Enter 로 못 받는다. Tab 으로는 여전히 들어간다.
    - `editor.quickSuggestions` 끄기: 변수, 함수 이름도 저절로 안 뜬다.
    - `C_Cpp.autocomplete: "disabled"`: C/C++ 자동 완성 전부.
  - cpptools 에는 조각 하나만 끄는 설정이 없다. 그래서 cpptools 코드 조각 21개가 같이 꺼지는 것이 가장 좁다.
- WSL: 단축키와 달리 설정에는 원격 자리(Machine 설정)가 있다. VSCode 서버 폴더 이름은 `.vscode-server`(1.144 제품 설정 `serverDataFolderName`), 원격 설정 파일은 그 아래 `data/Machine/settings.json` 이다. `VSCODE_AGENT_FOLDER` 를 쓰면 그 폴더를 따른다.

### 한글 입력: EditContext 끄기 (`lib/settings.sh`, task469)
- 증상: 한글을 치면 커서가 엉뚱한 곳으로 튀고 글자가 다른 자리에 한 번 더 써진다. 맥에서 가끔, WSL 노트북(Ubuntu 터미널에서 `code .`)에서 자주.
- 원인: VSCode 편집기는 글자 입력을 브라우저의 EditContext API 로 받는다. 한글처럼 조합해서 치는 입력(IME)에서 이 통로가 커서 자리와 조합 중인 글자를 어긋나게 받는 일이 있다.
  - 1.144.0 본체: `editContext` 는 편집기 옵션(boolean, 기본 `true`), 옛 이름 `editor.experimentalEditContextEnabled` 값은 새 이름으로 옮겨 읽는다.
  - 편집기 화면은 이 값이 참이면 EditContext 입력부를, 거짓이면 숨은 textarea 입력부를 만든다(`_instantiateEditContext`). 설정이 바뀌면 그 자리에서 입력부를 새로 만든다(`_updateEditContext`). 그래서 창을 다시 열 필요가 없다.
- 끄는 설정: `"editor.editContext": false`. 2026-11-08 동혁님 WSL 노트북에서 이것 하나로 고쳐짐을 확인.
  - 함께 바뀌는 것: 편집기가 글자 입력을 받는 통로 하나. 다른 편집 기능과 설정은 그대로.
- WSL 자리를 정한 근거(1.144.0 `workbench.desktop.main.js`)
  - 편집기 옵션은 모두 `editor.<이름>` 으로 `id: "editor"` 설정 묶음에 등록되고, 그 묶음의 scope 는 `6` 이다. 확장 설정 글자를 숫자로 바꾸는 표에서 `"language-overridable"` 이 `6` 이다.
  - Remote-WSL 원격 설정(`RemoteUserConfiguration`)은 scope `[2,3,4,5,6,7]` 만 읽는다. 빠진 것은 `1`(application) 하나다.
  - 그래서 `editor.editContext` 는 원격 설정 `~/.vscode-server/data/Machine/settings.json` 에서 먹고, 원격 설정은 Windows 쪽 사용자 설정보다 나중에 읽혀 이긴다. Windows 쪽 파일은 건드리지 않는다.
  - 이 값은 메인 프로세스가 아니라 창(렌더러)의 편집기가 설정 서비스에서 읽는다(`out/main.js` 에는 이 키가 없다). 창의 설정 서비스에는 원격 설정이 합쳐져 있다.
- 칸 둘: `settings.json` 에 vsc 칸이 `cpp-snippets`, `edit-context` 둘이다.
  - `vsc_part` 는 칸을 맨 바깥 `{` 바로 뒤에 넣고, `{` 와 같은 줄에 글이 있으면 그 줄을 갈라 넣은 뒤 칸 처음 줄에 `[split]` 을 단다(빼면 다시 붙인다).
  - 칸 하나만 빼면 깨진다. 실제로 `{"editor.fontSize": 14}` 한 줄 파일에 cpp-snippets, edit-context 순으로 넣고 cpp-snippets 만 빼면, 사용자 글 `"editor.fontSize": 14}` 가 edit-context 끝 줄(주석)에 붙고, 이어서 edit-context 를 빼면 그 줄째 지워져 `{` 만 남았다. 남은 칸의 끝 쉼표도 틀어진다.
  - 그래서 `st_update` 는 사본에서 vsc 칸을 위에서부터 모두 뺀 다음, 켜 둘 칸만 정한 순서(`ST_PARTS`: cpp-snippets, edit-context)로 다시 넣고, 바이트가 다를 때만 원래 파일과 바꾼다. 맨 위 칸은 늘 `{` 바로 뒤라 갈라 넣은 줄도 제자리로 붙는다.
  - 다른 칸이 깨져 있으면(처음 줄만 있고 끝 줄이 없음) 아무것도 바꾸지 않고 알린다.

## 4. 사용 흐름
```bash
# 최초 1회 (PC당)
cd ~/github/plzrun-vscode-gcc-setup && bash install.sh

# 그 다음부터, 새 문제 폴더에서 한 줄
vsc                 # → ./.vscode 생성 (옛 이름 plzrun-vscode-gcc-setup 도 같다)
vsc -stdin in2      # 입력 파일 바꾸기
vsc --init          # 새 문제: 설정을 처음 상태로
```
그 폴더를 VSCode로 열고(회사면 Remote-WSL): `Ctrl+Shift+B`(release 빌드) / `F5`(debug 디버깅) / 터미널 태스크로 `run release`, `run exam (timed)` 등.

---

## 5. 의존성 / 라이선스
- 의존: `bash`, `awk`, `g++`, `code` CLI, (디버깅 시)`gdb`/`lldb`, (확장)`ms-vscode.cpptools`.
- 패키지매니저/네트워크 불필요(생성기는 템플릿 채우기뿐). 시험 도구 `test/vscode_sim.py` 만 python3 를 쓴다.
- 라이선스: MIT.

---

## 6. 자매 도구
- **포맷 자동정렬**은 별도 repo `plzrun-auto-indent`(astyle + vim/VSCode 연동). 이 repo는 **컴파일/디버그 세팅 생성**만 담당. 둘은 독립.
