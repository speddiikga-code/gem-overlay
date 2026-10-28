export const meta = {
  name: 'legion',
  description: 'Agent legion: a recursive task tree where each agent solves its task or splits it for child agents, then results merge back up level by level',
  whenToUse: 'Fan one large task out across many agents and many levels. Preview the tree with mode "plan" before a full "run".',
  phases: [
    { title: 'Depth 0', detail: 'the root agent solves the goal or splits it' },
    { title: 'Merge', detail: 'each parent combines its children, deepest first' },
    { title: 'Review', detail: 'a completeness critic checks the final result' },
  ],
}

// args: { goal, mode: 'plan' | 'run', preset, maxDepth, minDepth, maxAgents, branching, context, isolation: 'worktree',
//         review, effort, mergeEffort, model }
// The tree is kept by this script, so depth costs no context: each agent sees only its own node and the titles above it.
const PRESETS = {
  tiny: { maxAgents: 12, maxDepth: 3, branching: 3 },
  squad: { maxAgents: 40, maxDepth: 5, branching: 4 },
  legion: { maxAgents: 300, maxDepth: 12, branching: 6 },
  max: { maxAgents: 950, maxDepth: 40, branching: 8 },
}

const A = typeof args === 'string' ? { goal: args } : (args ?? {})
if (!A.goal || !String(A.goal).trim()) throw new Error('legion needs args.goal: the task to distribute')
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.round(Number(v))))
const base = PRESETS[A.preset] ?? PRESETS.squad
const goal = String(A.goal).trim()
const mode = A.mode === 'run' ? 'run' : 'plan'
const maxDepth = clamp(A.maxDepth ?? base.maxDepth, 1, 40)
// The workflow runtime stops at 1000 agents; the margin keeps merges and the review possible.
const maxAgents = clamp(A.maxAgents ?? base.maxAgents, 3, 950)
const branching = clamp(A.branching ?? base.branching, 2, 12)
// Levels above minDepth must split, for a guaranteed pyramid shape even when agents would rather solve.
const minDepth = clamp(A.minDepth ?? 0, 0, maxDepth)
const brief = A.context ? String(A.context).trim() : ''
const isolation = A.isolation === 'worktree' ? 'worktree' : undefined
const review = mode === 'run' && A.review !== false
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const pickEffort = v => (EFFORTS.includes(v) ? v : undefined)
// A plan only decides how to split, and a merge needs judgment but no deep search, so both default
// below the session's effort; that is most of a legion's thinking tokens.
const decideEffort = pickEffort(A.effort) ?? (mode === 'plan' ? 'low' : undefined)
const mergeEffort = pickEffort(A.mergeEffort) ?? 'medium'
const model = typeof A.model === 'string' && A.model ? A.model : undefined
const opts = o => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined))

const mergeCost = mode === 'run' ? 1 : 0
let reserved = 1 + (review ? 1 : 0)
const stats = { agents: 0, splits: 0, leaves: 0, deepest: 0, failed: 0 }
const budgetOk = () => !budget.total || budget.remaining() > 40000

const DECIDE = {
  type: 'object',
  properties: {
    action: { type: 'string', enum: ['solve', 'split'] },
    result: { type: 'string', description: 'solve: the full deliverable (plan mode: what doing it involves and produces)' },
    subtasks: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'three to eight words' },
          task: { type: 'string', description: 'self-contained task statement with the expected deliverable' },
        },
        required: ['title', 'task'],
      },
    },
    rationale: { type: 'string', description: 'one or two sentences: why solve or why this split' },
  },
  required: ['action', 'rationale'],
}

const MERGE = {
  type: 'object',
  properties: {
    result: { type: 'string', description: 'only the combined deliverable, exactly as the reader should get it' },
    gaps: { type: 'array', items: { type: 'string' }, description: 'what the task needs that no subtask covered' },
    notes: { type: 'string', description: 'merge decisions: what was dropped or changed and why' },
  },
  required: ['result'],
}

const REVIEW = {
  type: 'object',
  properties: {
    complete: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'string' }, description: 'what is missing, wrong or unsupported, most important first' },
  },
  required: ['complete', 'issues'],
}

const short = s => (s.length > 40 ? s.slice(0, 39) + '…' : s)

function decidePrompt(node, canSplit, k) {
  const doWork = mode === 'run'
    ? 'Do it fully and put the deliverable in "result".'
    : 'Do not do the work: this is a planning preview. In "result" describe in two to four sentences what doing it involves and produces.'
  const choice = canSplit && node.depth < minDepth
    ? `Split: this level of the tree must split. Break the task into 2 to ${k} subtasks that together cover all of it, do not overlap, and can each be done without seeing the others' output. Give each a short title and a self-contained task statement that names the expected deliverable. Do not do the work yourself.`
    : canSplit
    ? `Choose one:
- solve: the task is focused enough for one agent to do well in one sitting. ${doWork}
- split: the task is too broad for one agent. Break it into 2 to ${k} subtasks that together cover all of it, do not overlap, and can each be done without seeing the others' output. Give each a short title and a self-contained task statement that names the expected deliverable. Do not do the work yourself.
Prefer solve when splitting would only add overhead.`
    : `Splitting is not available at this node (depth or agent limit reached). Solve the task. ${doWork}`
  return `You are one agent in a legion: a tree of agents working toward one goal. Each agent sees only its own node.

Root goal: ${goal}
${brief ? `Shared brief for every agent: ${brief}\n` : ''}Your node: ${node.id}, depth ${node.depth} of at most ${maxDepth}.
Path from the root: ${node.path.join(' > ')}
Your task: ${node.task}

${choice}

Keep "rationale" to one sentence. Return the deliverable itself, with no preamble or closing remarks.`
}

function mergePrompt(node, children) {
  const parts = children.map(c => {
    const text = String(c.result ?? '')
    const cut = text.length > 8000 ? text.slice(0, 8000) + '\n[cut at 8000 characters]' : text
    return `<subtask id="${c.id}" title="${c.title}">\n${cut}\n</subtask>`
  }).join('\n\n')
  return `You are node ${node.id} (depth ${node.depth}) in an agent legion.
Root goal: ${goal}
${brief ? `Shared brief: ${brief}\n` : ''}Your task: ${node.task}

You split this task into ${children.length} subtasks, each done by its own agent or sub-tree. Combine their results into the single deliverable for your task: keep what is correct and needed, remove repetition, and resolve contradictions. "result" holds only the deliverable, in the shape the task asks for: no remarks about merging, and no sections the task did not ask for. Put what you dropped or changed, and why, in "notes"; put anything the task needs that no subtask covered in "gaps" instead of writing it yourself.

${parts}`
}

async function runNode(node) {
  stats.deepest = Math.max(stats.deepest, node.depth)
  const k = Math.min(branching, maxAgents - reserved - mergeCost)
  const canSplit = node.depth < maxDepth && k >= 2 && budgetOk()
  // Reserve this node's children and merge before waiting, so concurrent nodes can never overspend the agent limit.
  const hold = canSplit ? k + mergeCost : 0
  reserved += hold
  const out = { id: node.id, depth: node.depth, title: node.title, task: node.task }

  const d = await agent(decidePrompt(node, canSplit, k), opts({
    label: `L${node.depth} ${node.id} ${short(node.title)}`,
    phase: `Depth ${node.depth}`,
    schema: DECIDE,
    isolation,
    effort: decideEffort,
    model,
  }))
  stats.agents++
  const subs = d && d.action === 'split' && canSplit ? (d.subtasks ?? []).filter(s => s && s.task).slice(0, k) : []
  if (!d || subs.length < 2) {
    reserved -= hold
    stats.leaves++
    if (!d) stats.failed++
    return { ...out, action: 'solve', rationale: d?.rationale ?? 'agent returned nothing', result: d ? (d.result || d.rationale) : '' }
  }

  reserved -= k - subs.length
  stats.splits++
  log(`${node.id} split into ${subs.length} at depth ${node.depth + 1}; ${reserved}/${maxAgents} agents reserved`)
  const children = await Promise.all(subs.map((s, i) => runNode({
    id: `${node.id}.${i + 1}`,
    depth: node.depth + 1,
    title: s.title,
    task: s.task,
    path: [...node.path, s.title],
  })))
  const split = { ...out, action: 'split', rationale: d.rationale, children }
  if (mode === 'plan') return split

  const m = await agent(mergePrompt(node, children), opts({ label: `merge ${node.id} ${short(node.title)}`, phase: 'Merge', schema: MERGE, effort: mergeEffort, model }))
  stats.agents++
  if (!m) stats.failed++
  return {
    ...split,
    result: m ? m.result : children.map(c => `## ${c.title}\n\n${c.result}`).join('\n\n'),
    gaps: m?.gaps ?? [],
    notes: m?.notes ?? '',
  }
}

function outline(n, lines = []) {
  const kind = n.action === 'split' ? `split ${n.children.length}` : 'leaf'
  lines.push(`${'  '.repeat(n.depth)}${n.id} ${n.title} [${kind}]`)
  for (const c of n.children ?? []) outline(c, lines)
  return lines
}

log(`legion ${mode}: up to ${maxAgents} agents, depth ${maxDepth}, ${branching} children per split`)
const root = await runNode({ id: '1', depth: 0, title: 'Root', task: goal, path: ['Root'] })

let critique = null
if (review) {
  critique = await agent(`Check this result against its goal. Say what is missing, wrong, or unsupported, most important first. Do not rewrite it.

Goal: ${goal}
${brief ? `Brief: ${brief}\n` : ''}
<result>
${root.result}
</result>`, { label: 'review', phase: 'Review', schema: REVIEW })
  stats.agents++
}

return {
  goal,
  mode,
  limits: opts({ maxAgents, maxDepth, minDepth, branching, effort: decideEffort, mergeEffort, model }),
  stats,
  outline: outline(root).join('\n'),
  final: mode === 'run' ? root.result : null,
  review: critique,
  tree: root,
}
