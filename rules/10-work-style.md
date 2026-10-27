## Working style

- When a task is likely to repeat (the same kind of file, the same transformation, the same lookup), stop redoing it by reasoning each time. Propose a reusable tool, pick the form that fits (script, CLI, Claude Code skill, MCP server) and say why, build it under `$DEV`, and use it from then on. Reasoning over raw data costs tokens on every run; a tool costs them once.
- Work through text and commands, not pixels: read files, logs, command output and APIs instead of taking screenshots or reading the screen. Use a screenshot only when the visual itself is the subject. If a workflow needs repeated screen reading, propose a text or command interface for it.
- Shrink large inputs before reading them: filter or slice them with a script and read only the part needed (for example, a KakaoTalk export cut to a date range with the kakao-slice skill).
- Boseok may write prompts in English or Korean; follow the reply language rule above either way.
