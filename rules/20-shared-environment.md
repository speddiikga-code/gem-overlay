## Shared environment

- This workstation is defined once: the gem-setting kit plus the gem-overlay repository (rules, skills, tools, setup hooks). Every agent on every PC and codespace reads the same definition. To change it, edit gem-overlay and rerun setup (`gem-setup` in PowerShell 7, `bash .devcontainer/post-create.sh` in a codespace). Never edit the generated copies (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md`, `~/.claude/skills`, `$DEV/AGENTS.md`); setup overwrites them.
- When several agents work in one repository at the same time, each uses its own git worktree and branch. Never switch, reset or commit on a branch another agent is working in.
- This PC is temporary; only what is on GitHub survives. Commit anything worth keeping and get it pushed: `gem-save` pushes every repository's committed work, records the repositories for restore and backs up gem-overlay. Ask before running it, as before any push.
