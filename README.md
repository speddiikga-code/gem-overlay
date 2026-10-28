# gem-overlay

Boseok's personal layer on top of the gem-setting kit. The kit in `$env:DEV\gem-setting` stays
unchanged; this folder adds his git identity, extra apps, agent rules and Claude Code skills, and
the scripts that back the workstation up to GitHub and rebuild it on another PC or in a GitHub
Codespace. The kit's setup reads it when you point it here once.

GitHub is the single source of truth: the private repositories `gem-setting` (the kit) and
`gem-overlay` (this folder), plus the projects listed in `repos.txt`. Moving to a new PC or to the
cloud, step by step in Korean: [MIGRATE.ko.md](MIGRATE.ko.md).

## Apply it

In a new Windows Terminal (PowerShell 7), after the kit itself has run once so that `DEV` is set:

```powershell
pwsh "$env:DEV\gem-setting\setup.ps1" -Apps -Overlay "$env:DEV\gem-overlay"
```

Setup saves the folder as the user variable `DEVSTARTER_OVERLAY`, so later runs of `START.cmd` or
`setup.ps1` use it without `-Overlay`. Running it again is safe: only what changed is written.
After that, new PowerShell 7 windows have `gem-setup` (the same as running `setup.ps1`; arguments
are passed on), `gem-save` and `gem-restore-help`.

## What each file does

| File | What it does |
|---|---|
| `config.json` | git name and email, the name in the agent rules, `DEV` (`%SystemDrive%\Dev`, which is `C:\Dev` on most PCs), reply language Korean, and extra winget apps (ripgrep, jq) |
| `rules\10-work-style.md` | appended to the global agent rules in `~\.claude\CLAUDE.md` (and the Codex, Gemini and OpenCode copies): build reusable tools for repeated work, read text instead of screenshots, shrink large inputs first |
| `rules\20-shared-environment.md` | appended the same way: the environment is defined here, generated copies are not edited, parallel agents use their own worktree and branch, work worth keeping goes to GitHub |
| `setup.d\10-claude-code.ps1` | installs the Claude Code CLI with the official installer when `claude` is missing |
| `setup.d\20-claude-skills.ps1` | copies each folder in `skills\` to `~\.claude\skills\`, writing only files that changed |
| `setup.d\30-profile.ps1` | writes the PowerShell 7 profile for all hosts (`Documents\PowerShell\profile.ps1`) with `gem-save`, `gem-setup` and `gem-restore-help`; the kit's own `Microsoft.PowerShell_profile.ps1` is left alone |
| `setup.d\40-cloud-export.ps1` | copies the generated global rules, `$env:DEV\AGENTS.md` and the kit's git hooks into `cloud\` with LF endings, for the codespace |
| `save.ps1` | the routine backup (`gem-save`), below |
| `restore.cmd`, `restore.ps1` | rebuild the workstation on a new Windows PC from GitHub, below |
| `repos.txt` | the GitHub repositories under `DEV` that restore clones, one `owner/name relative\path` per line; `gem-save` rewrites it |
| `cloud\` | what the codespace reads, kept current by `40-cloud-export.ps1`; do not edit it by hand |
| `.devcontainer\` | the GitHub Codespaces definition (Ubuntu, Node LTS, GitHub CLI) and `post-create.sh`, which installs uv, Python 3.13 and Claude Code and applies `cloud\` and `skills\` |
| `skills\kakao-slice\` | a Claude Code skill for KakaoTalk chat exports (below) |
| `skills\legion\` | the agent legion: a workflow that spreads one task over a tree of agents (below) |
| `site\gem-setting-3d.html` | source of the interactive 3D overview page published as a Claude artifact |
| `site\legion-board.html` | source of the legion mission board, a gift to NaNIsaac: a mission planner plus a shared board, published as a Claude artifact |
| `.gitattributes` | LF for shell scripts, hooks, `cloud\` and `.devcontainer\`; CRLF for `.cmd` and `.ps1` |
| `.gitignore` | keeps Python caches, `.bak` files, and an agent's `.claude\worktrees\` and `.claude\settings.local.json` out of git (gem-save stages everything else here) |

## Adding things

Each change takes effect the next time setup runs:

```powershell
pwsh "$env:DEV\gem-setting\setup.ps1"
```

- A rule: add a file such as `rules\30-python.md` that starts with a `## Heading`. Files in
  `rules\` are appended in name order.
- An app: find its id with `winget search <name>`, add it to the `winget` list in `config.json`,
  and run setup with `-Apps`.
- A skill: create `skills\<name>\SKILL.md` with `name` and `description` at the top (see
  `skills\kakao-slice\SKILL.md`). To copy skills without the rest of setup:
  `pwsh "$env:DEV\gem-overlay\setup.d\20-claude-skills.ps1"`. Edit skills here, not in
  `~\.claude\skills`: setup replaces a changed file there with the copy from this folder.

Then run `gem-save` so the change reaches GitHub and the codespace.

## Back it up: gem-save

```powershell
gem-save
```

For every git repository under `DEV` (two levels deep), and every linked worktree of one (an
agent's, for example), it prints one line: clean and pushed, uncommitted changes, commits not
pushed, or no remote. It pushes each branch that has an upstream and commits the upstream lacks,
rewrites `repos.txt` from the repositories whose `origin` is on github.com, refreshes `cloud\`,
then commits this folder as `chore: save workstation state` and pushes it. After a change in
`rules\`, run `gem-setup` first: until then the generated rules lack it, so `cloud\CLAUDE.md` is
left as it is and gem-save says so. It never commits another repository's changes; it lists them, and exits 1 until
nothing is left only on this PC. `gem-save -DryRun` shows all of this without changing anything.
Without the profile: `pwsh "$env:DEV\gem-overlay\save.ps1"`.

The first time, create the two private repositories (sign in once with `gh auth login`; it opens
the browser). `config.json` holds your email, so keep them private:

```powershell
gh repo create gem-setting --private --source "$env:DEV\gem-setting" --push
gh repo create gem-overlay --private --source "$env:DEV\gem-overlay" --push
```

## Restore on a new Windows PC

```powershell
winget install --id Git.Git -e --source winget
winget install --id GitHub.cli -e --source winget
```

Open a new terminal, then:

```powershell
gh auth login
gh repo clone gem-overlay "$env:SystemDrive\Dev\gem-overlay"
& "$env:SystemDrive\Dev\gem-overlay\restore.cmd"
```

`restore.cmd` runs `restore.ps1` with the Windows PowerShell that ships with Windows. It checks
that git and gh are installed and signed in, lets git use the gh sign-in (`gh auth setup-git`),
pulls this folder, clones `gem-setting` next to it (or pulls it), clones each `repos.txt` entry
that is missing, then runs the kit's `bootstrap.ps1 -Overlay <this folder> -Dev <its parent>`,
which installs the apps and applies everything here. `restore.cmd -DryRun` prints each step
without doing it. A failed pull or clone is listed at the end and the rest still runs; running it
again is safe.

## Cloud workstation: GitHub Codespaces

On the repository page on GitHub: Code, Codespaces, Create codespace on main. Or:

```powershell
gh codespace create -R "$(gh api user --jq .login)/gem-overlay"
```

Open it from a local terminal (the codespace runs an SSH server for this) or in VS Code:

```powershell
gh codespace ssh
gh codespace code
```

`.devcontainer\post-create.sh` then installs uv, Python 3.13 and Claude Code, copies `cloud\CLAUDE.md`
to the Claude, Codex, Gemini and OpenCode rule files, the skills to `~/.claude/skills`, the git
hooks to `~/.config/git/hooks` (as `core.hooksPath`), sets Claude Code's `attribution`, sets the git
identity from `config.json` when none is set, and writes `/workspaces/AGENTS.md` and
`/workspaces/CLAUDE.md` so every repository cloned under `/workspaces` gets the rules. Run
`claude` there once to sign in. To apply a newer overlay inside a running codespace:
`git pull` and `bash .devcontainer/post-create.sh`. Stop a codespace you are not using
(`gh codespace stop`); the free monthly quota is counted while it runs.

Claude Code on the web (claude.ai/code) works on these GitHub repositories directly, without a PC.

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

## legion skill

Spreads one task over a tree of agents. Each agent either does its task or splits it into
self-contained subtasks for child agents; parents merge their children's results, deepest level
first, and a critic reviews the final result. The script keeps the tree, so depth costs no context.

In Claude Code, ask for it by name, for example "legion으로 이 작업 나눠서 해 줘: <task>". It
previews the tree first (`mode: plan`), then runs with the size you pick: `tiny` (12 agents),
`squad` (40), `legion` (300) or `max` (950 agents, 40 levels). One workflow runs up to 16 agents at
a time and 1000 in total. Arguments and details: [skills/legion/SKILL.md](skills/legion/SKILL.md).
Results go to `$env:DEV\legion-runs\`.
