# plzrun-vscode-gcc-setup (`vsc`)

C/C++ 문제 폴더에 **VSCode 빌드, 실행, 디버그 세팅(`.vscode/`)을 한 명령으로 만드는** 도구.
세팅한 뒤에도 같은 명령으로 언어 표준과 입출력 파일을 바꾼다.

- 짧은 이름은 `vsc`. 옛 이름 `plzrun-vscode-gcc-setup` 도 같은 프로그램이다.
- 빌드는 외부 의존성 없이 `g++` 만 쓴다. 생성기도 `bash` 와 `awk` 만 쓴다.
- Windows 는 Remote-WSL(Ubuntu) 안에서 쓰는 것을 전제로 한다. macOS native 도 같다.
- 화면에 나오는 글은 전부 영어다(한글이 깨지는 터미널 대비).

## 설치 / 제거

```bash
cd ~/github/plzrun-vscode-gcc-setup
bash install.sh      # 명령 vsc, plzrun-vscode-gcc-setup 설치 + cpptools 확장 설치
bash uninstall.sh    # 명령 제거 (각 폴더의 .vscode/ 는 그대로)
```

- 이미 다른 프로그램이 `~/.local/bin/vsc` 를 쓰고 있으면 덮지 않고 알린다. 그때는 옛 이름으로 쓰면 된다.

## 두 가지 방식

처음 세팅할 때 폴더를 보고 저절로 고른다. `--ex`, `--single` 로 정할 수도 있다.

| 방식 | 언제 | 빌드 대상 | 실행 파일 |
|---|---|---|---|
| **ex** | 폴더에 `main.cpp` 가 있음 (sw_expert) | `main.cpp` + 지금 보고 있는 파일 | `pgm_exam`, `pgm_release`, `pgm_debug` |
| **single** | `main.cpp` 가 없음 (BOJ, poj) | 지금 보고 있는 파일 하나 | 그 파일 옆에 파일 이름대로 (`14216/14216.cpp` -> `14216/14216`) |

single 방식은 문제 모음 폴더 맨 위에 **한 번만** 깐다.

```
~/github/poj/            <- 여기서 vsc 한 번 (VSCode 도 이 폴더로 연다)
├── .vscode/
├── 14216/
│   ├── 14216.cpp        <- 이 탭을 보고 Ctrl+Shift+B / F5
│   ├── in
│   └── in2
└── 1199/ ...
```

## 사용

```bash
vsc                          # 세팅 안 된 폴더: 기본값으로 세팅 / 세팅된 폴더: 현재 설정 보기
vsc -lang c++17              # 언어 표준 바꾸기 (기본 c++14)
vsc -stdin in2               # 입력 파일 바꾸기 (기본 in)
vsc -stdout out2             # 출력을 파일로 (기본은 터미널)
vsc -stdin in2 -stdout out2  # 여러 개를 한 번에
vsc -stdout default          # 하나만 기본값으로
vsc --init                   # 모든 설정을 처음 상태로 (새 문제 시작)
vsc --remove                 # vsc 가 만든 파일 지우기 (설정이 꼬였을 때 지우고 다시 vsc)
vsc --help
```

옵션 규칙은 하나다.

- 값이 붙는 옵션은 대시 하나: `-lang`, `-stdin`, `-stdout`
- 값이 없는 옵션은 대시 둘: `--init`, `--remove`, `--ex`, `--single`, `--force`, `--help`

그 밖의 규칙:

- 따로 설치 단계가 없다. 세팅 안 된 폴더에서 `vsc` 를 치면(옵션이 있어도) 기본 세팅부터 만든다.
- 입출력 파일 이름은 **지금 보고 있는 파일과 같은 폴더** 기준이다. `/` 로 시작하면 그 경로 그대로.
- 문제 폴더(`poj/14216`) 안에서 `vsc -stdin in2` 를 쳐도 된다. 위쪽에서 세팅된 폴더(`poj`)를 찾아서 바꾼다.
- 휴대폰 자동 고침으로 `—init` 처럼 긴 대시가 들어가도 `--init` 으로 읽는다.

## 화면에 나오는 글 (예시)

처음 세팅:

```
$ vsc
vsc: set up /Users/me/github/poj
  mode:   single  (only the file you are viewing)  [no main.cpp here]
  lang:   c++14
  stdin:  in  (in the folder of the file you are viewing)
  stdout: terminal
  .vscode: created vsc.conf, tasks.json, launch.json
  Ctrl+Shift+B: build the file you are viewing (-O2).  F5: debug it (-g).
  Tasks: run release (uses stdin/stdout above).
```

바꾼 것과 안 바뀐 것:

```
$ vsc -stdin in2
vsc: updated /Users/me/github/poj
  stdin:  in -> in2
  .vscode: rewrote vsc.conf, tasks.json, launch.json

$ vsc -lang c++17
vsc: nothing changed in /Users/me/github/poj (lang is already c++17)

$ vsc --init
vsc: reset /Users/me/github/poj to the default settings
  lang:   c++17 -> c++14
  stdin:  in2 -> in
  .vscode: rewrote vsc.conf, tasks.json, launch.json
```

잘못 쳤을 때 (git 처럼 가까운 것을 알려 준다):

```
$ vsc -stdn in2
vsc: error: unknown option '-stdn'

Did you mean '-stdin'?

$ vsc -lang c++41
vsc: error: unknown value for -lang: 'c++41'
  example: vsc -lang c++17
  values:  c++11 c++14 c++17 c++20 c++23 (default c++14)

Did you mean 'c++14'?

$ vsc -lang
vsc: error: option '-lang' needs a value
  example: vsc -lang c++17
  values:  c++11 c++14 c++17 c++20 c++23 (default c++14)

$ vsc -init
vsc: error: unknown option '-init'
  options without a value use two dashes

Did you mean '--init'?

$ vsc —init
vsc: note: read '—init' as '--init' (a long dash was replaced)
```

없는 입력 파일을 고르면 설정은 바꾸고 알린다:

```
$ vsc -stdin in3
vsc: updated /Users/me/github/poj
  stdin:  in2 -> in3
  .vscode: rewrote vsc.conf, tasks.json, launch.json
vsc: warning: no file named 'in3' next to your sources yet (setting saved; runs read from the terminal until it exists)

Did you mean one of these?
	in
	in2
```

## 생성되는 빌드 구성 (`.vscode/tasks.json`)

ex 방식 (`-lang` 값이 `-std=` 로 들어간다):

| 태스크 | 명령 | 산출물 |
|---|---|---|
| build exam (시험 옵션, 타임 측정) | `g++ -std=c++14 -O0 main.cpp ${file} -o pgm_exam` | `pgm_exam` |
| build release (`Ctrl+Shift+B`) | `g++ -std=c++14 -O2 main.cpp ${file} -o pgm_release` | `pgm_release` |
| build debug (F5) | `g++ -std=c++14 -g main.cpp ${file} -o pgm_debug` | `pgm_debug` |
| run release / run exam (timed) | 빌드 후 실행, `in` 이 있으면 `< in` | |

- 풀이 `.cpp` 를 **활성 탭**으로 둔 채 빌드나 F5 를 한다(main.cpp 를 보고 있으면 중복 컴파일된다).

single 방식:

| 태스크 | 명령 |
|---|---|
| build release (`Ctrl+Shift+B`) | `g++ -std=c++14 -O2 ${file} -o ${fileDirname}/${fileBasenameNoExtension}` |
| build debug (F5) | `g++ -std=c++14 -g ${file} -o ${fileDirname}/${fileBasenameNoExtension}` |
| run release | 빌드 후 실행, `in` 이 있으면 `< in` |

- 실행할 때 입력 파일이 없으면 리다이렉트 없이 돌리고 경고 한 줄을 낸다:
  `vsc warning: stdin file not found: .../in (reading from the terminal)`
- `-stdout` 을 정하면 실행 뒤 `vsc: stdout was written to .../out2` 를 낸다.

## 디버깅 (`.vscode/launch.json`)

- **F5** -> `vsc: prepare F5` (debug 빌드 + 입력 준비) 후 디버깅.
- **Ctrl+F5** (Run Without Debugging) -> 같은 준비 뒤 디버거 없이 터미널에서 실행.
- F5 와 Ctrl+F5 모두 `-stdin`, `-stdout` 설정을 따른다.
  - 준비 단계가 입력 파일을 `.vscode/vsc-f5-stdin` 으로 복사한다. 입력 파일이 없으면 빈 파일을 두고 경고한다.
  - `args` 에 `< .vscode/vsc-f5-stdin` (출력 파일이 있으면 `> out2`). Linux/WSL `gdb` 의 F5 와 모든 OS 의 Ctrl+F5 는 이 줄을 셸로 돌리므로 리다이렉트가 먹는다.
  - macOS `lldb` 의 F5 는 `args` 를 셸로 돌리지 않는다. 그래서 `settings set target.input-path` (출력은 `target.output-path`)로 따로 넣는다.
  - 이 때문에 macOS F5 에서는 프로그램 argv 에 `<` 와 파일 이름이 함께 들어간다. argv 를 읽지 않는 풀이에는 상관없다.
- 필요 확장: `ms-vscode.cpptools` (install.sh 가 설치).
- Linux/WSL 에서 F5 를 쓰려면 `gdb` 가 있어야 한다(빌드와 실행에는 필요 없다).

## Shift+Esc = Esc

- `vsc` 로 세팅한 폴더 안의 파일에서는 VSCode 의 Shift+Esc 가 Esc 와 똑같이 동작한다.
  - Vim(VSCodeVim) 입력 모드 빠져나가기, 자동 완성 닫기, 찾기 창 닫기, 여러 커서 해제, 매개변수 힌트 닫기, 빠른 열기와 알림 닫기 등 Esc 의 일 전부다.
- VSCode 는 단축키를 프로젝트(`.vscode/`) 단위로 두지 못한다. 단축키는 사용자 `keybindings.json` 하나에서만 읽는다.
  - 그래서 `vsc` 가 사용자 `keybindings.json` 에 표시 주석(`// >>> vsc shift+escape` ~ `// <<< vsc shift+escape`)으로 묶은 칸을 넣는다.
  - 칸 안 단축키마다 "Esc 의 원래 조건 && 파일이 그 폴더 안"(`resourcePath =~ /^(폴더)\//`) 조건이 붙는다. 다른 폴더에서는 Shift+Esc 가 예전 그대로다.
- 사용자가 넣은 항목은 한 글자도 바꾸지 않는다. 칸은 배열 맨 앞에 들어간다.
- 같은 폴더에서 다시 쳐도 칸은 하나다. 폴더가 여럿이면 칸 안 `// vsc-folder:` 줄에 모은다.
- `vsc --remove` 는 그 폴더를 칸에서 뺀다. 마지막 폴더가 빠지면 칸이 통째로 빠지고 파일은 원래 바이트로 돌아간다. `uninstall.sh` 는 칸 전체를 뺀다.
- 파일이 JSON 배열(`[`)로 시작하지 않거나 표시가 깨져 있으면 손대지 않고 경고만 낸다.
- 자리: macOS `~/Library/Application Support/Code/User/keybindings.json`, Linux `~/.config/Code/User/keybindings.json`. WSL 에서는 VSCode 단축키가 Windows 쪽에 있어서 넣지 않고 알린다.
- Esc 단축키 목록은 `templates/shift-esc.tsv` 다. VSCode 1.143.1 기본 81개, 내장 copilot 1개, VSCodeVim 2개이고, `tools/gen-shift-esc.py` 로 다시 만든다.
- 칸이 효과를 내는 때는 지금 보고 있는 편집기 파일이 그 폴더 안일 때다. 편집기가 하나도 열려 있지 않으면 Shift+Esc 는 VSCode 기본 동작을 따른다.

## 설정 파일과 지우기

- 설정은 `.vscode/vsc.conf` 하나에 있다. `tasks.json`, `launch.json` 은 명령을 칠 때마다 이 설정으로 다시 만든다. 손으로 고치지 않는다.
- `vsc` 가 만들지 않은 `tasks.json`, `launch.json` 이 이미 있으면 덮지 않고 멈춘다. 바꾸려면 `--force`. 백업 사본(`.bak`)은 만들지 않는다.
- 옛 버전이 만든 파일은 이 도구 것으로 알아보고 새 형식으로 바꾼다.
- `vsc --remove` 는 `vsc` 가 만든 파일(`vsc.conf`, `tasks.json`, `launch.json`, `vsc-f5-stdin`)만 지운다. 빌드한 실행 파일은 지우지 않는다. Shift+Esc 칸에서도 그 폴더를 뺀다.

## 시험

```bash
bash test/check.sh <ex 문제 폴더> <poj 문제 폴더>
```

- 두 폴더를 `test/work/` 로 복사해(원본은 읽기만) 모든 명령을 돌리고 출력을 남긴다.
- Shift+Esc 칸은 시험용 `keybindings.json`(`VSC_KEYBINDINGS`)에만 쓴다. 실제 사용자 파일은 건드리지 않는다.
  - `test/kb_check.py`: 엄격한 JSON 읽기(주석 빼고 끝 쉼표 없음), 사용자 항목 그대로, Esc 규칙마다 vsc 항목 하나.
  - 같은 파일로 무작위 상태 2만 개와 Esc 규칙마다 그 규칙이 이기는 상태 하나씩을 만든다. 폴더 안에서는 Shift+Esc 가 Esc 와 같은 명령을 고르고, 폴더 밖에서는 vsc 규칙이 하나도 걸리지 않아야 한다.
  - `test/vscode_when.js`: 같은 검사를 설치된 VSCode 본체의 조건식 분석기와 평가기로 한다(본체 번들에서 그 부분을 떼어 node 로 돌림).
- `test/vscode_sim.py` 가 VSCode 처럼 변수를 바꿔 태스크를 돌리고, F5 는 cpptools 의 `lldb-mi` 를 같은 순서로 몰아 입력이 들어가는지 본다(macOS). Ctrl+F5 는 cpptools 1.34.4 가 만드는 것과 같은 터미널 명령 줄을 셸로 돌린다.

## 구성

```
plzrun-vscode-gcc-setup/
├── install.sh / uninstall.sh
├── setup.sh                 # 생성기 (vsc 명령의 본체)
├── lib/
│   └── keybindings.sh       # Shift+Esc 칸 넣기와 빼기 (setup.sh, uninstall.sh 공용)
├── templates/
│   ├── tasks.ex.json        # ex 방식 태스크
│   ├── tasks.single.json    # single 방식 태스크
│   ├── launch.json          # F5 (두 방식 공용)
│   └── shift-esc.tsv        # Esc 에 묶인 VSCode 단축키 전부 (명령, 조건)
├── tools/
│   └── gen-shift-esc.py     # shift-esc.tsv 만들기 (개발할 때만)
├── test/
│   ├── check.sh
│   ├── vscode_sim.py
│   ├── kb_check.py          # Shift+Esc 칸 검사
│   ├── vscode_when.js       # 설치된 VSCode 의 조건식 분석기로 검사
│   └── fixtures/keybindings-user.jsonc
├── HOW_IT_WORKS.md
├── LICENSE                  # MIT
└── README.md
```

## 라이선스

MIT (루트 `LICENSE`).
