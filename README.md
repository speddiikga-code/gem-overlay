# gem-overlay

Boseok's personal layer on top of the gem-setting kit. The kit in `$env:DEV\gem-setting` stays
unchanged; this folder adds his git identity, extra apps, agent rules and Claude Code skills.
The kit's setup reads it when you point it here once.

## Apply it

In a new Windows Terminal (PowerShell 7), after the kit itself has run once so that `DEV` is set:

```powershell
pwsh "$env:DEV\gem-setting\setup.ps1" -Apps -Overlay "$env:DEV\gem-overlay"
```

Setup saves the folder as the user variable `DEVSTARTER_OVERLAY`, so later runs of `START.cmd` or
`setup.ps1` use it without `-Overlay`. Running it again is safe: only what changed is written.

## What each file does

| File | What it does |
|---|---|
| `config.json` | git name and email, the name in the agent rules, `DEV` (`%SystemDrive%\Dev`, which is `C:\Dev` on most PCs), reply language Korean, and extra winget apps (ripgrep, jq) |
| `rules\10-work-style.md` | appended to the global agent rules in `~\.claude\CLAUDE.md` (and the Codex, Gemini and OpenCode copies): build reusable tools for repeated work, read text instead of screenshots, shrink large inputs first |
| `setup.d\05-uv-python.ps1` | sets `UV_PYTHON_PREFERENCE=only-managed`: on this PC the WindowsApps `python.exe` is the Python install manager, and letting uv probe it silently installs another Python |
| `setup.d\10-claude-code.ps1` | installs the Claude Code CLI with the official installer when `claude` is missing |
| `setup.d\20-claude-skills.ps1` | copies each folder in `skills\` to `~\.claude\skills\`, writing only files that changed |
| `skills\kakao-slice\` | a Claude Code skill for KakaoTalk chat exports (below) |
| `.gitignore` | keeps Python caches and `.bak` files out of git |

## Adding things

Each change takes effect the next time setup runs:

```powershell
pwsh "$env:DEV\gem-setting\setup.ps1"
```

- A rule: add a file such as `rules\20-python.md` that starts with a `## Heading`. Files in
  `rules\` are appended in name order.
- An app: find its id with `winget search <name>`, add it to the `winget` list in `config.json`,
  and run setup with `-Apps`.
- A skill: create `skills\<name>\SKILL.md` with `name` and `description` at the top (see
  `skills\kakao-slice\SKILL.md`). To copy skills without the rest of setup:
  `pwsh "$env:DEV\gem-overlay\setup.d\20-claude-skills.ps1"`. Edit skills here, not in
  `~\.claude\skills`: setup replaces a changed file there with the copy from this folder.

## Back it up as a private GitHub repository

`config.json` holds your email, so keep the repository private. Sign in once (it opens the browser):

```powershell
gh auth login
```

Then:

```powershell
cd "$env:DEV\gem-overlay"
git add -A
git commit -m "chore: initial overlay"
gh repo create gem-overlay --private --source . --push
```

After later changes: `git add -A`, `git commit -m "<what changed>"`, `git push`. On another PC,
after the kit has run there:

```powershell
gh repo clone gem-overlay "$env:DEV\gem-overlay"
pwsh "$env:DEV\gem-setting\setup.ps1" -Apps -Overlay "$env:DEV\gem-overlay"
```

## kakao-slice skill

Cuts a KakaoTalk chat export down to the dates you need, so an agent reads a small slice instead
of the whole file. Details: [skills/kakao-slice/SKILL.md](skills/kakao-slice/SKILL.md).

In Claude Code, attach or name the export (`대화 내용 내보내기` in the chat room menu) and ask
what you want; the skill runs the script for you. In a terminal:

```powershell
uv run "$HOME\.claude\skills\kakao-slice\kakao_slice.py" "KakaoTalk_chat.txt" --list
uv run "$HOME\.claude\skills\kakao-slice\kakao_slice.py" "KakaoTalk_chat.txt" --from 2026-10-01 --to 2026-10-27 -o slice.txt
```

`--list` shows messages per date; then pick a slice with `--date`, `--from`/`--to`, `--last N`,
`--sender`, `--grep`, and save it with `-o`. `--help` lists every option and supported format.
Tests: `uv run --with pytest pytest skills\kakao-slice\tests -q`.
