# 작업 환경을 다른 PC나 클라우드로 옮기기

이 노트북은 곧 없어집니다. 남는 것은 GitHub에 올라간 것뿐입니다. 이 문서대로 하면 다른 Windows
PC에서든, PC 없이 클라우드(GitHub Codespaces)에서든 같은 작업 환경을 다시 만들 수 있습니다.

아래 명령은 Windows Terminal(PowerShell)에 그대로 붙여 넣으면 됩니다. `%DEV%`는 프로젝트 폴더이고
보통 `C:\Dev`입니다.

## 무엇이 어디에 있나

| 무엇 | GitHub (비공개 저장소) | 이 PC의 위치 |
|---|---|---|
| 설치 키트: 앱 목록, 터미널 설정, 에이전트 규칙, git hook | `gem-setting` | `%DEV%\gem-setting` |
| 내 설정: 이름과 이메일, 추가 규칙, 스킬, 백업과 복원 스크립트, Codespaces 설정 | `gem-overlay` | `%DEV%\gem-overlay` |
| 내 프로젝트 | 프로젝트마다 각자의 저장소, 목록은 `gem-overlay\repos.txt` | `%DEV%` 아래 |

`repos.txt`는 직접 고치지 않아도 됩니다. `gem-save`가 `%DEV%` 아래에서 GitHub에 연결된 저장소를 찾아
다시 씁니다.

## 백업되지 않는 것

- 로그인: GitHub(`gh auth login`), Claude(`claude` 첫 실행 때 브라우저 로그인), 브라우저와 그 밖의
  계정. 새 PC에서 다시 로그인합니다. 비밀번호와 토큰은 파일로 옮기지 말고 비밀번호 관리자에 둡니다.
- `%DEV%` 밖의 파일: 문서, 다운로드, 바탕 화면, 사진. 필요한 것은 OneDrive나 USB로 따로 옮깁니다.
- 아직 GitHub에 없는 작업: 커밋하지 않은 변경, stash, push하지 않은 브랜치, GitHub 저장소(remote)가
  없는 폴더. `gem-save`가 `%DEV%` 아래 두 단계 깊이까지의 저장소와 그 worktree에서 찾아 보여 줍니다.
  그보다 깊은 곳(예: `%DEV%\a\b\c`)의 저장소는 보지 않으니 두 단계 안에 둡니다.
- `.gitignore`에 걸린 파일: `.env` 같은 비밀 값, 로컬 데이터, `.venv`(다시 만들 수 있음).
- Claude Code 대화 기록(`~\.claude\projects`), PowerShell 명령 기록, VS Code 설정(필요하면 VS Code의
  Settings Sync를 켭니다).

## 매일 습관: gem-save

작업을 마칠 때마다 Windows Terminal에서:

```powershell
gem-save
```

저장소마다 한 줄씩 상태를 보여 주고, 할 수 있는 것은 직접 합니다.

| 표시 | 뜻 | 할 일 |
|---|---|---|
| `clean and pushed` | 전부 GitHub에 있음 | 없음 |
| `pushed main +2` | 방금 커밋 2개를 push함 | 없음 |
| `uncommitted changes (3 files)` | 커밋하지 않은 변경 | 그 저장소에서 커밋(에이전트에게 "커밋해 줘"라고 해도 됨)하고 `gem-save` 다시 |
| `commits not pushed: x +1 (no upstream)` | 한 번도 push하지 않은 브랜치 | 그 저장소에서 `git push -u origin x` |
| `no remote` | GitHub 저장소가 없음 | 그 폴더에서 `gh repo create <이름> --private --source . --push` |
| `1 stash (not backed up)` | stash에 넣어 둔 변경 | 꺼내서 커밋하거나 버림 |
| `push failed` | push 실패 | 아래 나온 git 메시지를 읽음. 보통 그 저장소에서 `git pull` 뒤 `gem-save` 다시 |
| `run gem-setup first` | 규칙(`rules\`)을 바꾼 뒤 설정을 아직 다시 적용하지 않아 codespace용 규칙을 갱신하지 않음 | `gem-setup` 뒤 `gem-save` 다시 |

마지막 줄이 초록색 `save: everything is on GitHub.`이면 끝입니다. 노란 목록이 남으면 아직 이 PC에만
있는 것이 있다는 뜻입니다. `gem-overlay`의 변경은 `gem-save`가 직접 커밋하고 push합니다.

무엇을 할지 미리 보기만 하려면(아무것도 바꾸지 않음):

```powershell
gem-save -DryRun
```

`gem-save`를 찾을 수 없다고 나오면, 설정을 한 번 다시 적용하고 새 터미널을 엽니다:

```powershell
pwsh "$env:DEV\gem-setting\setup.ps1"
```

## 처음 한 번: GitHub에 올리기

이미 했다면 건너뜁니다. 아래 명령이 저장소 정보를 보여 주면 이미 된 것입니다:

```powershell
gh repo view gem-overlay
```

아직이면 GitHub에 로그인합니다. 질문에는 GitHub.com, HTTPS, Authenticate Git with your GitHub
credentials에 Yes, Login with a web browser를 고르고 브라우저에서 승인합니다:

```powershell
gh auth login
```

그다음 두 저장소를 비공개로 만듭니다. `config.json`에 이메일이 있으므로 반드시 `--private`입니다:

```powershell
gh repo create gem-setting --private --source "$env:DEV\gem-setting" --push
gh repo create gem-overlay --private --source "$env:DEV\gem-overlay" --push
gem-save
```

## 새 Windows PC에서 복원

1. Windows Terminal(또는 시작 메뉴의 PowerShell)을 열고 Git과 GitHub CLI를 설치합니다. Windows가
   권한을 물으면 허용합니다.

   ```powershell
   winget install --id Git.Git -e --source winget
   winget install --id GitHub.cli -e --source winget
   ```

2. 그 창을 닫고 새 터미널을 엽니다. 새로 설치한 프로그램은 새 창에서만 보입니다.

3. GitHub에 로그인하고(질문은 위 "처음 한 번"과 같음), 내 설정을 받아 복원을 시작합니다:

   ```powershell
   gh auth login
   gh repo clone gem-overlay "$env:SystemDrive\Dev\gem-overlay"
   & "$env:SystemDrive\Dev\gem-overlay\restore.cmd"
   ```

   `restore.cmd`가 하는 일: git과 gh 로그인 확인, `gem-overlay` 최신으로 받기, `gem-setting`을 옆에
   clone, `repos.txt`의 프로젝트 clone, 그리고 키트 설치(PowerShell 7, Windows Terminal, VS Code, uv,
   Node.js, Python 3.13, Claude Code, 규칙, 스킬, git hook, `gem-save` 명령). 몇 분 걸리고 중간에
   Windows 권한 창이 뜨면 허용합니다. 끝나면 "아무 키나 누르십시오"가 나옵니다. 중간에 실패한
   단계는 끝에 목록으로 나오고, `restore.cmd`를 다시 실행하면 그 부분만 다시 합니다.

   실제로 하기 전에 할 일만 보고 싶으면:

   ```powershell
   & "$env:SystemDrive\Dev\gem-overlay\restore.cmd" -DryRun
   ```

4. 창을 닫고 새 Windows Terminal을 열어 Claude에 로그인합니다(브라우저가 열림):

   ```powershell
   claude
   ```

5. 확인: 모든 줄이 `clean and pushed`인지 봅니다.

   ```powershell
   gem-save
   ```

`C:\Dev`가 아닌 곳(예: `D:\Dev`)에 두려면 3번의 `"$env:SystemDrive\Dev\gem-overlay"`를 원하는
위치로 바꿉니다. `gem-overlay`가 들어 있는 폴더가 그 PC의 `%DEV%`가 됩니다.

## 클라우드 작업 공간: GitHub Codespaces

PC 없이 브라우저만으로 같은 규칙, 스킬, git hook이 있는 Linux 작업 공간을 씁니다.

만들기: GitHub의 `gem-overlay` 저장소 페이지에서 Code, Codespaces, Create codespace on main.
또는 터미널에서:

```powershell
gh codespace create -R "$(gh api user --jq .login)/gem-overlay"
```

처음 만들 때 몇 분 동안 `.devcontainer/post-create.sh`가 uv, Python 3.13, Claude Code를 설치하고
규칙, 스킬, git hook, git 이름과 이메일을 적용합니다. 끝나면 codespace의 터미널에서 `claude`를
실행해 로그인합니다.

- 다시 열기: https://github.com/codespaces 또는 `gh codespace code`(VS Code), `gh codespace ssh`.
- `/workspaces` 아래에 clone한 저장소는 모두 같은 규칙을 받습니다. 다만 codespace의 기본 권한은 만든
  저장소(`gem-overlay`) 하나라서 다른 비공개 저장소는 clone이 거부될 수 있습니다. 다른 프로젝트는
  아래 Claude Code on the web이 가장 쉽습니다.
- codespace 안에서 한 작업도 커밋하고 push해야 남습니다(`gem-save`는 Windows용이고, 여기서는
  `git push`).
- PC에서 설정을 바꾸고 `gem-save`한 뒤 실행 중인 codespace에 반영하려면 codespace 터미널에서:

  ```bash
  git pull
  bash .devcontainer/post-create.sh
  ```

비용: GitHub 개인 계정에는 매달 무료 사용량(실행 시간과 저장 용량)이 있고, 남은 양은
https://github.com/settings/billing 에서 봅니다. 실행 중인 시간만큼 줄어드니 쓰지 않을 때는 멈춥니다.
아무것도 하지 않으면 기본 30분 뒤 자동으로 멈추지만, 직접 멈추는 편이 확실합니다:

```powershell
gh codespace stop
```

멈춘 codespace도 저장 용량은 차지합니다. 더 쓰지 않을 codespace는 push할 것이 없는지 확인한 뒤
`gh codespace delete`로 지웁니다. 지우면 그 안에서 push하지 않은 작업은 사라집니다.

## Claude Code on the web

https://claude.ai/code 에서 GitHub 계정을 연결하면 `gem-overlay`, `gem-setting`, `repos.txt`의 프로젝트
어느 것이든 PC 없이 Claude Code로 작업할 수 있습니다. 결과는 GitHub의 브랜치와 pull request로
남습니다. 웹 세션에는 이 PC의 `~\.claude\CLAUDE.md` 같은 전역 규칙 파일이 없고, 저장소 안의
`CLAUDE.md`를 읽습니다. 웹에서도 꼭 지켜야 할 규칙은 그 저장소의 `AGENTS.md`에 두고, 같은 폴더에
`@AGENTS.md` 한 줄만 쓴 `CLAUDE.md`를 함께 둡니다(`%DEV%`의 두 파일과 같은 방식).

## 설정을 바꿀 때

규칙(`rules\`), 스킬(`skills\`), 추가 앱(`config.json`)은 `gem-overlay`에서 바꾸고 다음을 실행합니다.
`~\.claude\CLAUDE.md` 같은 생성된 파일을 직접 고치면 다음 설정 때 덮어써집니다.

```powershell
gem-setup
gem-save
```

이 문서가 어디 있는지 잊었으면:

```powershell
gem-restore-help
```
