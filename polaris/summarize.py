#!/usr/bin/env python3
"""Summarize a perf_agents.pbs run: one row per agent run, then medians.

usage: summarize.py <OUT dir> <job log>
Reads <OUT>/<agent>_<i>/agent.jsonl (Claude Code stream-json or clio-coder
--json events) and the AGENT lines of the job log. Times:
  wall    the whole CLI run, start-up included (job script)
  LLM     time inside model calls: Claude Code duration_api_ms; clio-coder,
          the sum of each assistant message's modelTimeMs
  Python  the workflow's Python calls (python shim)
  other   wall - LLM - Python: CLI start-up, agent loop, tool overhead
"""
import json, re, statistics, sys
from datetime import datetime
from pathlib import Path

AGENTS = ["claude", "alcf", "nemotron"]


def claude_metrics(lines):
    m = {"tools": 0, "empty": 0}
    ids = set()
    for e in lines:
        if e.get("type") == "assistant":
            msg = e.get("message", {})
            ids.add(msg.get("id"))
            m["tools"] += sum(1 for c in msg.get("content", []) if c.get("type") == "tool_use")
        if e.get("type") == "result":
            u = e.get("usage", {})
            m.update(llm_s=e.get("duration_api_ms", 0) / 1000,
                     tokens_in=u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                     + u.get("cache_read_input_tokens", 0),
                     cache_read=u.get("cache_read_input_tokens", 0),
                     tokens_out=u.get("output_tokens", 0), cost=e.get("total_cost_usd"),
                     answer=e.get("result", ""))
    m["llm_calls"] = len(ids - {None})
    return m


def clio_metrics(lines):
    m = {"tools": 0, "empty": 0, "llm_s": 0.0, "llm_calls": 0, "ttft": []}
    for e in lines:
        t = e.get("type")
        if t == "tool_execution_start":
            m["tools"] += 1
        elif t == "message_end" and "modelTimeMs" in e:
            m["llm_calls"] += 1
            m["llm_s"] += e["modelTimeMs"] / 1000
            if e.get("ttftMs") is None:
                m["empty"] += 1          # the stream never produced a token
            else:
                m["ttft"].append(e["ttftMs"] / 1000)
        elif t == "agent_end":
            u = e.get("usage", {})
            m.update(tokens_in=u.get("input", 0), tokens_out=u.get("output", 0))
        elif t == "turn_end":
            c = (e.get("message") or {}).get("content")
            text = " ".join(x.get("text", "") for x in c if isinstance(x, dict)) if isinstance(c, list) else (c or "")
            if text.strip():
                m["answer"] = text
    return m


def main(out, log):
    out = Path(out)
    rows = []
    for line in open(log):
        mm = re.match(r"AGENT (\S+) run(\d+) wall=([\d.]+)s rc=(\d+) python_calls=(\d+) python_s=([\d.]+) "
                      r"results_ok=(\S+) scripts_edited=(\S+)", line)
        if not mm:
            continue
        agent, i = mm[1], int(mm[2])
        f = out / f"{agent}_{i}" / "agent.jsonl"
        lines = []
        for l in open(f) if f.exists() else []:
            try:
                lines.append(json.loads(l))
            except Exception:
                pass
        m = claude_metrics(lines) if agent == "claude" else clio_metrics(lines)
        nums = re.findall(r"(\d{3}\.\d)\s*MPa", " ".join((m.get("answer") or "").split()))
        answered = int(mm[4]) == 0 and {"178.5", "193.9"} <= set(nums)
        wall, py = float(mm[3]), float(mm[6])
        rows.append(dict(agent=agent, i=i, wall=wall, py=py, llm=m.get("llm_s", 0), other=wall - m.get("llm_s", 0) - py,
                         calls=m.get("llm_calls", 0), empty=m["empty"], tools=m.get("tools", 0),
                         tin=m.get("tokens_in", 0), tout=m.get("tokens_out", 0), cost=m.get("cost"),
                         rc=int(mm[4]), ok=mm[7], edited=mm[8], answered=answered,
                         ttft=statistics.median(m["ttft"]) if m.get("ttft") else None))
    rows.sort(key=lambda r: (AGENTS.index(r["agent"]) if r["agent"] in AGENTS else 9, r["i"]))

    print("| agent | run | wall (s) | LLM (s) | Python (s) | other (s) | LLM calls | empty LLM replies | tool calls "
          "| input / output tokens | cost (USD) | rc | workflow ran OK | answered | scripts edited |")
    print("|" + "---|" * 15)
    for r in rows:
        cost = f"{r['cost']:.3f}" if r["cost"] is not None else "–"
        print(f"| {r['agent']} | {r['i']} | {r['wall']:.1f} | {r['llm']:.1f} | {r['py']:.2f} | {r['other']:.1f} | {r['calls']} "
              f"| {r['empty']} | {r['tools']} | {r['tin']:,} / {r['tout']:,} | {cost} | {r['rc']} | {r['ok']} "
              f"| {'yes' if r['answered'] else '**no**'} | {r['edited']} |")

    print("\nMedians over all runs (and over runs 2–5, without the first, cold run):\n")
    print("| agent | answered | wall (s) | wall, runs 2–5 (s) | LLM (s) | Python (s) | other (s) | LLM calls | input tokens "
          "| output tokens | cost per run (USD) |")
    print("|" + "---|" * 11)
    for a in AGENTS:
        rs = [r for r in rows if r["agent"] == a]
        if not rs:
            continue
        med = lambda k, rr=rs: statistics.median(r[k] for r in rr)
        warm = [r for r in rs if r["i"] > 1] or rs
        cost = f"{statistics.mean(r['cost'] for r in rs):.3f}" if rs[0]["cost"] is not None else "0 (allocation)"
        print(f"| {a} | {sum(r['answered'] for r in rs)}/{len(rs)} | {med('wall'):.1f} | {med('wall', warm):.1f} | {med('llm'):.1f} "
              f"| {med('py'):.2f} | {med('other'):.1f} | {med('calls'):.0f} | {med('tin'):,.0f} | {med('tout'):,.0f} | {cost} |")


if __name__ == "__main__":
    main(*sys.argv[1:3])
