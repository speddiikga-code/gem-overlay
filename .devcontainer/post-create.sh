#!/usr/bin/env bash
# Makes a GitHub Codespace built from this repository the same workstation as the Windows PCs: uv
# with Python 3.13, Claude Code, the global rules for Claude, Codex, Gemini and OpenCode, the
# skills, the git hooks and identity, and the rules for every repository under /workspaces. It reads
# only this repository (cloud/, skills/, config.json), which gem-save keeps current on Windows.
# Safe to run again: a file is written only when it differs.
#   GEM_SKIP_INSTALL=1     skip the network installs (uv, Python, Claude Code)
#   GEM_WORKSPACES=<dir>   use <dir> instead of /workspaces
set -euo pipefail

overlay="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cloud="$overlay/cloud"
workspaces="${GEM_WORKSPACES:-/workspaces}"
declare -A missing=()
export PATH="$HOME/.local/bin:$PATH"

step() { printf -- '-> %s\n' "$1"; }

copy_if_changed() {
    if [ ! -f "$1" ]; then
        missing["$1"]=1
        return 0
    fi
    cmp -s "$1" "$2" && return 0
    mkdir -p "$(dirname "$2")"
    cp "$1" "$2"
    printf '   wrote %s\n' "$2"
}

# Prints config.json's git.<key>, or nothing.
config_git() {
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg key "$1" '.git[$key] // empty' "$overlay/config.json"
    else
        node -e 'const c = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8")); process.stdout.write(c.git?.[process.argv[2]] ?? "")' \
            "$overlay/config.json" "$1"
    fi
}

if [ "${GEM_SKIP_INSTALL:-}" = 1 ]; then
    step 'installs skipped (GEM_SKIP_INSTALL=1)'
else
    step 'uv and Python 3.13'
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
    uv python install 3.13 --default
    step 'Claude Code'
    command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
fi

step 'agent rules: Claude, Codex, Gemini, OpenCode'
for target in .claude/CLAUDE.md .codex/AGENTS.md .gemini/GEMINI.md .config/opencode/AGENTS.md; do
    copy_if_changed "$cloud/CLAUDE.md" "$HOME/$target"
done

step "skills -> $HOME/.claude/skills"
for skill in "$overlay"/skills/*/; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    # Test suites and caches are for developing a skill, not for Claude Code to load.
    while IFS= read -r file; do
        copy_if_changed "$skill$file" "$HOME/.claude/skills/$name/$file"
    done < <(cd "$skill" && find . -type d \( -name tests -o -name __pycache__ -o -name .pytest_cache \) -prune -o -type f -print | sed 's|^\./||' | sort)
done

step 'Claude Code: no co-author, PR or session lines'
settings="$HOME/.claude/settings.json"
attribution='{"commit":"","pr":"","sessionUrl":false}'
mkdir -p "$(dirname "$settings")"
[ -s "$settings" ] || printf '{}\n' >"$settings"
if command -v jq >/dev/null 2>&1; then
    if ! jq -e --argjson want "$attribution" '.attribution == $want' "$settings" >/dev/null; then
        jq --argjson want "$attribution" '.attribution = $want' "$settings" >"$settings.tmp"
        mv "$settings.tmp" "$settings"
        printf '   wrote %s\n' "$settings"
    fi
else
    node -e '
        const fs = require("node:fs");
        const [file, wanted] = process.argv.slice(1);
        const settings = JSON.parse(fs.readFileSync(file, "utf8"));
        if (JSON.stringify(settings.attribution) === wanted) process.exit(0);
        settings.attribution = JSON.parse(wanted);
        fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
        console.log(`   wrote ${file}`);
    ' "$settings" "$attribution"
fi

step "git hooks -> $HOME/.config/git/hooks"
hooks="$HOME/.config/git/hooks"
copy_if_changed "$cloud/git-hooks/commit-msg" "$hooks/commit-msg"
copy_if_changed "$cloud/git-hooks/pre-push" "$hooks/pre-push"
# A global core.hooksPath hides each repository's .git/hooks, so every other hook name the kit's
# setup.ps1 installs is a copy of forward-hook, which hands over to the repository's own hook.
# The list repeats setup.ps1's; change both together.
for name in applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit \
            prepare-commit-msg post-commit pre-rebase post-checkout post-merge post-rewrite pre-auto-gc \
            pre-receive update post-receive post-update proc-receive sendemail-validate; do
    copy_if_changed "$cloud/git-hooks/forward-hook" "$hooks/$name"
done
if [ -d "$hooks" ]; then chmod +x "$hooks"/*; fi
if [ "$(git config --global --get core.hooksPath || true)" != "$hooks" ]; then
    git config --global core.hooksPath "$hooks"
    printf '   core.hooksPath = %s\n' "$hooks"
fi

# Codespaces puts the GitHub login in /etc/gitconfig; checking only the user's own (global) value lets
# config.json win there, so commits from the cloud carry the same name as those from the PC.
step 'git: identity from config.json where the user has not set one'
for key in name email; do
    if [ -z "$(git config --global --get "user.$key" || true)" ]; then
        value="$(config_git "$key")"
        if [ -n "$value" ]; then
            git config --global "user.$key" "$value"
            printf '   user.%s set\n' "$key"
        fi
    fi
done

# Claude Code reads every CLAUDE.md from its working directory up, so one in /workspaces covers each
# repository cloned there, as $DEV\CLAUDE.md does on Windows.
step "rules for every repository under $workspaces"
if [ -d "$workspaces" ] && [ -w "$workspaces" ]; then
    copy_if_changed "$cloud/AGENTS.md" "$workspaces/AGENTS.md"
    if ! printf '@AGENTS.md\n' | cmp -s - "$workspaces/CLAUDE.md"; then
        printf '@AGENTS.md\n' >"$workspaces/CLAUDE.md"
        printf '   wrote %s\n' "$workspaces/CLAUDE.md"
    fi
else
    printf '   %s is missing or not writable; skipped\n' "$workspaces"
fi

# Codespaces gives its own terminals a GITHUB_TOKEN but not SSH sessions (gh codespace ssh), where git
# pull/push and gh would then ask for a login; this loads the same token from the codespace's env file.
step 'GitHub token for SSH sessions'
marker='# gem-overlay: GitHub token for SSH sessions'
if [ -f "$HOME/.bashrc" ] && ! grep -qF "$marker" "$HOME/.bashrc"; then
    cat >>"$HOME/.bashrc" <<'EOF'

# gem-overlay: GitHub token for SSH sessions
if [ -z "${GITHUB_TOKEN:-}" ] && [ -r /workspaces/.codespaces/shared/.env ]; then
    GITHUB_TOKEN="$(sed -n 's/^GITHUB_TOKEN=//p' /workspaces/.codespaces/shared/.env)"
    export GITHUB_TOKEN
fi
EOF
    printf '   added to %s\n' "$HOME/.bashrc"
fi
# The Codespaces credential helper does not answer in SSH sessions either; gh, which reads that token,
# is added after it, so git falls back to gh there and the codespace's own terminals are unchanged.
gh_helper='!gh auth git-credential'
if command -v gh >/dev/null && ! git config --global --get-all credential.https://github.com.helper 2>/dev/null | grep -qxF "$gh_helper"; then
    git config --global --add credential.https://github.com.helper "$gh_helper"
    printf '   git uses gh for github.com credentials\n'
fi

if [ "${#missing[@]}" -gt 0 ]; then
    printf 'Missing from this repository, so their copies were skipped:\n' >&2
    printf '   %s\n' "${!missing[@]}" | sort >&2
    printf 'On the Windows PC run gem-save (it refreshes cloud/ and pushes), then here:  git pull && bash .devcontainer/post-create.sh\n' >&2
    exit 1
fi
printf 'Done. Run  claude  once to sign in.\n'
