---
name: legion
description: Distribute one large task across a multi-level tree of agents (an agent legion or pyramid) that split the work down and merge results back up. Use when the user asks for a legion, an agent pyramid or hierarchy, many agents or many levels, 에이전트 군단, 멀티 에이전트, 다단계 에이전트, or to spread a big task across agents. Runs the Workflow tool with legion.js.
---

# legion

Invoking this skill is the user's opt-in to multi-agent orchestration: run the Workflow tool as below.

Each node of the tree is one agent. It either solves its task or splits it into 2 to `branching`
self-contained subtasks for child agents; when the children finish, the parent merges their
results, deepest level first, and a critic reviews the final result. The script keeps the tree, so
each agent sees only its own task and the titles above it, and depth costs no context.

## Run it

The script is `legion.js` next to this file. Pass its absolute path, resolving the home folder
first (Windows `C:\Users\<name>\.claude\skills\legion\legion.js`, Linux
`/home/<name>/.claude/skills/legion/legion.js`):

1. Preview the tree first. It is cheap: agents only decide how to split, nobody does the work.

   ```
   Workflow({ scriptPath: "<home>/.claude/skills/legion/legion.js",
              args: { goal: "<the task>", mode: "plan", preset: "squad" } })
   ```

2. Show the user the returned `outline` and `stats`, then run it for real with the limits they choose:

   ```
   Workflow({ scriptPath: "<home>/.claude/skills/legion/legion.js",
              args: { goal: "<the task>", mode: "run", preset: "squad", context: "<shared brief>" } })
   ```

3. Save the run with the report script, passing the output file named in the workflow's
   completion notice (`.../tasks/<id>.output`). It writes `result.json` and `report.md` to
   `$DEV/legion-runs/<date>-<mode>-<slug>/` and prints that folder:

   ```
   uv run "<home>/.claude/skills/legion/legion_report.py" "<task output file>"
   ```

   `$DEV/legion-runs` is a git repository backed up to GitHub: commit the new folder there
   (`git -C "$DEV/legion-runs" add -A`, then commit and push). Give the user the folder path and a
   short summary; read `report.md` rather than the raw JSON when you need details.

If the user has no goal yet, preview a goal they name, or ask for one; do not invent work to run.

## Arguments

| Key | Default | Meaning |
|---|---|---|
| `goal` | required | the task to distribute |
| `mode` | `plan` | `plan` builds the tree only; `run` does the work, merges and reviews |
| `preset` | `squad` | `tiny` 12 agents, depth 3, 3 children; `squad` 40, 5, 4; `legion` 300, 12, 6; `max` 950, 40, 8 |
| `maxAgents` | preset | hard limit on agents in the run, 3 to 950 |
| `maxDepth` | preset | deepest level, 1 to 40 |
| `branching` | preset | most children per split, 2 to 12 |
| `minDepth` | 0 | levels above this must split, for a guaranteed pyramid even on a small goal |
| `context` | none | a brief every agent gets: repository path, constraints, output format |
| `isolation` | none | `worktree` gives every agent its own git worktree, for tasks that edit files in parallel |
| `review` | `true` | `false` skips the final critic |
| `effort` | `low` in plan mode, the session's in run mode | reasoning effort for the agents that solve or split: `low` to `max` |
| `mergeEffort` | `medium` | reasoning effort for the merges |
| `model` | the session's | a model for every solve, split and merge agent, for example `sonnet` or `haiku` for wide, simple work |

To save usage, count agents, not effort. Measured on this setup (2026-10-28): every agent costs
about 54k tokens however small its task, because most of that is its fixed starting context. Lower
effort mainly saves time (a three-level run went from 144 s to 63 s at `medium`; a plan preview from
74 s to 20 s at `low`) and makes agents split less. So: preview with `plan`, cap `maxAgents`, prefer
fewer, larger leaves, and use a smaller `model` when the leaves are simple.

## Facts to tell the user when they matter

- One workflow runs at most 16 agents at the same time (CPU count minus 2 on smaller PCs) and at
  most 1000 in total; the rest queue. Wider and deeper trees take longer, not more at once.
- Every agent uses the plan's usage. Preview with `plan`, then raise the preset step by step.
- Agents decide whether to split; a goal that is not broad stays shallow even with `max`.
- With `isolation: "worktree"`, each agent's file changes stay in its own worktree and branch;
  merging them is a separate step.
- Live progress: `/workflows`. Each depth is its own group (`Depth 0`, `Depth 1`, ...).
