# Repositories under $DEV

- Applies to every repository under `$DEV`; a repository's own AGENTS.md takes precedence.
- Modern code: read the target version from `pyproject.toml`, the lock file, or `package.json`, and use the most modern syntax and standard library it allows. Python tools: uv, ruff. No deprecated idioms, needless compatibility code, or new dependencies without a reason.
- No AI tells in code, docs, or commits: no emoji, marketing wording, comments that restate code, or AI credit lines or mentions. Badges are allowed when few and clean (release, CI, license, docs); no badge walls. Commits are short conventional commits under the repository's `git config user.*`.
- Never hardcode drive letters or user folders in paths; use `$DEV` and paths relative to the repository.
- When you find a significant bug while working (in your own change or anyone's), open an issue (symptom, cause, how to reproduce) and fix it in a commit that references the issue, so the fix leaves a record. Typos and cosmetic problems do not need one. Issue text follows the same no-AI-tells rule.
- Keep README install and first-run steps as copy-paste code blocks that actually work; change them together with the code they describe.
- Run the checks CI runs before you push (the `pre-push` hook does the ruff lint when the repository pins it; run the fast tests yourself). Do not push work in progress to an open pull request branch one commit at a time.
- Before ending a session, leave nothing only on disk that should be committed, and say what is left to do.
- A comment says why, which the code cannot: no numbered step comments, section banners, comments that restate the code, or `Note:`/`Important:` emphasis. Code comments, commit messages, pull requests and issues are in English unless the repository says otherwise.
