# /// script
# requires-python = ">=3.13"
# ///
"""Turn a legion workflow result into a run folder with result.json and report.md.

Accepts the workflow's task output file (with "result", "agentCount", "totalTokens") or the bare
return value. Writes to $DEV/legion-runs/<date>-<slug>/ unless -o is given, and prints the folder.
"""

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path


def slug(text: str) -> str:
    words = re.findall(r"[a-z0-9]+", text.lower())[:6]
    return "-".join(words) or "run"


def node_lines(node: dict, out: list[str]) -> None:
    kind = "split" if node.get("action") == "split" else "leaf"
    out += [f"### {node['id']} {node['title']} ({kind}, depth {node['depth']})", "", f"**Task:** {node['task']}", ""]
    if node.get("rationale"):
        out += [f"**Why:** {node['rationale']}", ""]
    if node.get("result"):
        out += [node["result"].strip(), ""]
    if node.get("gaps"):
        out += ["**Gaps:**", *[f"- {g}" for g in node["gaps"]], ""]
    if node.get("notes"):
        out += [f"**Merge notes:** {node['notes']}", ""]
    for child in node.get("children", []):
        node_lines(child, out)


def report(run: dict, meta: dict) -> str:
    stats, limits = run.get("stats", {}), run.get("limits", {})
    out = [
        f"# {run['goal'][:100]}",
        "",
        f"- Mode: {run['mode']}",
        f"- Date: {meta['date']}",
        "- Limits: " + ", ".join(f"{k} {v}" for k, v in limits.items()),
        "- Stats: " + ", ".join(f"{k} {v}" for k, v in stats.items()),
    ]
    if meta.get("tokens"):
        out.append(f"- Tokens: {meta['tokens']:,}")
    out += ["", "## Goal", "", run["goal"], "", "## Outline", "", "```", run.get("outline", ""), "```", ""]
    if run.get("final"):
        out += ["## Result", "", run["final"].strip(), ""]
    review = run.get("review")
    if review:
        out += ["## Review", "", f"Complete: {'yes' if review.get('complete') else 'no'}", ""]
        out += [f"- {issue}" for issue in review.get("issues", [])] + [""]
    out += ["## Every node", ""]
    node_lines(run["tree"], out)
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input", type=Path, help="the workflow task output file or a saved return value")
    parser.add_argument("-o", "--output", type=Path, help="run folder (default: $DEV/legion-runs/<date>-<slug>)")
    ns = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    data = json.loads(ns.input.read_text(encoding="utf-8-sig"))
    run = data.get("result", data)
    if not isinstance(run, dict) or "tree" not in run:
        print(f"{ns.input} does not hold a legion result (no 'tree')", file=sys.stderr)
        return 1
    today = dt.date.today().isoformat()
    meta = {"date": today, "tokens": data.get("totalTokens"), "agents": data.get("agentCount")}

    folder = ns.output or Path(os.environ.get("DEV", ".")) / "legion-runs" / f"{today}-{run['mode']}-{slug(run['goal'])}"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "result.json").write_text(json.dumps(run, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (folder / "report.md").write_text(report(run, meta), encoding="utf-8")
    print(folder)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
