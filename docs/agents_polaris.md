# Three agents running the workflow on Polaris

**Question:** how do Claude Opus 5.5, the clio agent with an ALCF model, and the clio agent with Nemotron 3 Nano compare when each runs this workflow on an ALCF Polaris compute node?

**Answer:** all three run the workflow correctly and never edit `scripts/`. They differ in speed, reliability and cost:

| agent | answered | wall time per run, median | of which LLM | LLM calls | input tokens | cost per run |
|---|---|---|---|---|---|---|
| Claude Code, Claude Opus 5.5 | **5/5** | 16.0 s | 10.0 s | 5 | 163k (88% cache reads) | $0.20 |
| clio agent, ALCF Sophia gpt-oss-120b | **4/5** (5/8 over both jobs) | 9.8 s, but 38–69 s when Sophia stalls | 4.7 s | 3 | 14k | ALCF allocation |
| clio agent, Nemotron 3 Nano on the node's A100 | **5/5** (7/8 over both jobs) | **7.4 s** | 3.2 s | 4 | 24k | node time |

- **Nemotron 3 Nano is the fastest** once its server is up: 7.3 s per warm run, with a median time to first token of 0.38 s. But the server costs about 100 s per job to stage and load (see below). In an earlier job it once wrote its tool call as plain text and stopped without running anything (issue 3).
- **Claude Opus 5.5 was the most reliable,** with 5 of 5 runs right. It is the slowest and the only one paid per run. Most of its input is the tool and integration definitions of this Claude Code installation, re-read from the cache on every call (issue 4).
- **ALCF gpt-oss-120b is fast when Sophia answers:** 9.5 s warm, with a 1.1 s median time to first token. But in 4 of its 8 runs, one call streamed nothing for 31–53 s. clio-coder recovered from one of these by retrying; three runs failed (issue 1).
- **The workflow itself takes 1.8 s** of each run. The rest is the agent: CLI start-up and the agent loop take 2.4–4.1 s, and the LLM takes 3–10 s.

## Setup

ALCF Polaris, `debug` queue, one node (AMD EPYC 7543P, 4× A100-SXM4-40GB), PBS job **7810513** (5 runs per agent) and an earlier job **7810470** (3 runs per agent; its Claude runs did not start, see issue 5). toam commit `1beb8e8`, Python 3.13.13, numpy 2.5.4, pandas 3.1.0, matplotlib 3.11.2: the same versions as the Vista runs. Job script [`polaris/perf_agents.pbs`](../polaris/perf_agents.pbs), log [`polaris/toam_agents_7810513.log`](../polaris/toam_agents_7810513.log), per-run agent events and Python timings in [`polaris/agents_7810513/`](../polaris/agents_7810513/), tables from [`polaris/summarize.py`](../polaris/summarize.py).

Every agent gets the task used on Vista (`vista/perf_agent.slurm`): run `generate_data.py`, then `analysis.py`, do not edit `scripts/`, and report the three endurance limits from `docs/results.md`. Each run starts in a fresh copy of `scripts/`. A `python` shim on `PATH` times every Python call.

| agent | how it runs | model |
|---|---|---|
| `claude` | Claude Code 2.1.317, `claude -p --model claude-opus-5-5 --output-format stream-json`. Tools allowed: Read, Glob, Grep, and exactly `python scripts/generate_data.py` and `python scripts/analysis.py`. Anything else needs approval, which headless mode denies. | Claude Opus 5.5, Anthropic API through the ALCF proxy |
| `alcf` | clio-coder 0.6.1, `clio-coder run --target alcf-sophia --autonomy yolo --no-delegate --json` | `openai/gpt-oss-120b` on ALCF Sophia (inference-api.alcf.anl.gov) |
| `nemotron` | clio-coder 0.6.1, same flags, `--target polaris-nemotron` | Nemotron 3 Nano 30B-A3B, Q4_K_M, Ollama 0.40.8 on GPU 0 of the same node, 131k context |

The clio agent runs with `--autonomy yolo` as on Vista, so it may run any command. Claude Code runs under the narrower allowlist above, because unrestricted permissions were not allowed in this session. Every run works in its own throwaway directory.

**Times.** *Wall* is the whole CLI run, start-up included. *LLM* is the time spent inside model calls: Claude Code's `duration_api_ms`, and for clio-coder the sum of each call's `modelTimeMs`. *Python* is the workflow (shim). *Other* = wall − LLM − Python: CLI start-up, the agent loop and tool overhead.

## Results (job 7810513)

**The workflow alone,** 5 timed iterations after one warm-up: 1.96, 1.93, 1.91, 1.85 s (iterations 2–5; 2.38 s for iteration 1), of which `generate_data.py` takes 0.60 s and `analysis.py` 1.29 s. Polaris is 1.5× slower than Vista's Grace core (1.25 s) and 1.9× faster than Ares (3.63 s).

| agent | run | wall (s) | LLM (s) | Python (s) | other (s) | LLM calls | empty LLM replies | tool calls | input / output tokens | cost (USD) | rc | workflow ran OK | answered | scripts edited |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude | 1 | 16.0 | 10.1 | 1.84 | 4.1 | 5 | 0 | 4 | 163,671 / 883 | 0.205 | 0 | yes | yes | no |
| claude | 2 | 15.7 | 9.8 | 1.81 | 4.1 | 5 | 0 | 4 | 162,955 / 745 | 0.200 | 0 | yes | yes | no |
| claude | 3 | 17.3 | 11.5 | 1.78 | 4.0 | 5 | 0 | 4 | 163,226 / 895 | 0.204 | 0 | yes | yes | no |
| claude | 4 | 16.0 | 10.0 | 1.78 | 4.2 | 5 | 0 | 4 | 163,154 / 811 | 0.202 | 0 | yes | yes | no |
| claude | 5 | 14.3 | 8.4 | 1.78 | 4.1 | 5 | 0 | 4 | 162,955 / 768 | 0.201 | 0 | yes | yes | no |
| alcf | 1 | 69.4 | 59.2 | 1.74 | 8.5 | 4 | 1 | 2 | 14,055 / 164 | – | 0 | yes | yes | no |
| alcf | 2 | 9.5 | 4.4 | 1.75 | 3.3 | 3 | 0 | 2 | 14,039 / 384 | – | 0 | yes | yes | no |
| alcf | 3 | 9.5 | 4.4 | 1.74 | 3.3 | 3 | 0 | 2 | 14,043 / 393 | – | 0 | yes | yes | no |
| alcf | 4 | 9.8 | 4.7 | 1.75 | 3.3 | 3 | 0 | 2 | 14,043 / 383 | – | 0 | yes | yes | no |
| alcf | 5 | 37.6 | 32.5 | 1.76 | 3.3 | 2 | 1 | 1 | 4,448 / 65 | – | 1 | yes | **no** | no |
| nemotron | 1 | 36.6 | 31.8 | 1.76 | 3.1 | 4 | 0 | 3 | 23,636 / 273 | – | 0 | yes | yes | no |
| nemotron | 2 | 7.5 | 3.3 | 1.76 | 2.5 | 4 | 0 | 3 | 23,598 / 185 | – | 0 | yes | yes | no |
| nemotron | 3 | 7.2 | 3.0 | 1.77 | 2.4 | 4 | 0 | 3 | 23,647 / 147 | – | 0 | yes | yes | no |
| nemotron | 4 | 7.2 | 3.0 | 1.77 | 2.3 | 4 | 0 | 3 | 23,636 / 151 | – | 0 | yes | yes | no |
| nemotron | 5 | 7.4 | 3.2 | 1.77 | 2.4 | 4 | 0 | 3 | 23,636 / 169 | – | 0 | yes | yes | no |

Medians (all 5 runs, and runs 2–5 without the first, cold run):

| agent | answered | wall (s) | wall, runs 2–5 (s) | LLM (s) | Python (s) | other (s) | LLM calls | input tokens | output tokens | cost per run (USD) |
|---|---|---|---|---|---|---|---|---|---|---|
| claude | 5/5 | 16.0 | 15.8 | 10.0 | 1.78 | 4.1 | 5 | 163,154 | 811 | 0.202 |
| alcf | 4/5 | 9.8 | 9.6 | 4.7 | 1.75 | 3.3 | 3 | 14,043 | 383 | 0 (allocation) |
| nemotron | 5/5 | 7.4 | 7.3 | 3.2 | 1.77 | 2.4 | 4 | 23,636 | 169 | 0 (allocation) |

*Workflow ran OK* means `docs/results.md` has the right values (178.5 MPa TO-AB, 193.9 MPa TO-VT). *Answered* means the run exited 0 and its final message reports them. Every answer gave 426.5 / 178.5 / 193.9 MPa.

- **Claude Opus 5.5.**
  - **Same 4 tool calls in every run:** `ls -R | head -50 && python scripts/generate_data.py`, then `python scripts/analysis.py; echo EXIT=$?`, which the allowlist denied ("A variable in this command can't be checked before it runs"), then plain `python scripts/analysis.py`, then Read `docs/results.md`.
  - **The denied call costs one round trip,** about 2 s. With wider permissions it would likely take 4 LLM calls instead of 5.
  - **Fixed overhead:** Claude Code's start-up and loop take about 4.1 s per run.
- **ALCF gpt-oss-120b.**
  - **Shortest path:** 3 calls (run both scripts, read the results, answer) and only 14k input tokens.
  - **Fast when Sophia answers:** 9.5 s per run, with a 1.1 s median time to first token.
  - **Run 1** waited 53 s on a reply that never came, then clio-coder retried and succeeded (69 s in total).
  - **Run 5** ran both scripts, then its final call streamed nothing for 31 s. It exited 1 with "provider stream ended without an assistant response or terminal tool result". The workflow had run, but the agent never reported the values.
- **Nemotron 3 Nano.**
  - **Calls:** 4 per run (one script per call, then read and answer). The median time to first token is 0.38 s, the shortest of the three; the model is on the same node.
  - **The first run is slow:** its first call waited 29.6 s for the first token. It was the first request after the model loaded. After that, the shared prompt prefix is cached and first calls take 1.7 s.
  - **Server start-up per job,** overlapped with the other agents in this job: copy the 23 GB model to local SSD, about 61 s of `ollama serve` start-up, and 11.6 s to load the model. The model takes 24.2 GB on one A100; the other three GPUs stay free.

### Compared with Vista

Vista's clio agent runs (job 1112674, clio-coder 0.6.4, same ALCF model, same task) took 12.4–12.9 s warm, of which about 7.5 s was LLM and agent loop. On Polaris a warm ALCF run takes 9.5 s, with 4.4 s of LLM. Different clio-coder versions and days, and Sophia's latency varies, so this is not a clean comparison of the machines. The workflow's own share is similar: 1.3 s on Vista and 1.75 s on Polaris.

## Issues

1. **ALCF Sophia sometimes streams nothing.** Over both jobs, 4 of 8 ALCF runs had one call that ended after 31–53 s with no tokens. In clio-coder this shows as "provider stream ended without an assistant response or terminal tool result" and exit 1. One run recovered by retrying; three failed (job 7810470 runs 2–3, job 7810513 run 5). The same error happened once on a login node before the jobs, where a retry 1 minute later answered in 8 s. A direct request to Sophia answered normally at that time, and the gpt-oss-120b jobs were running. So these are short stalls at Sophia or between Sophia and clio-coder, not an auth problem.
2. **A failed run can still have run the workflow.** ALCF run 5 ran both scripts correctly (`docs/results.md` is right) and then failed to answer. Judge an agent run by its outputs as well as its exit code.
3. **Nemotron once wrote its tool call as text.** In job 7810470 run 1, its only reply was text announcing a `bash` action, with the call as a JSON block in Markdown, not a real tool call. clio-coder then ended the run with exit 0 and nothing done. It worked in the other 7 runs.
4. **Claude Code's input is mostly this installation's own setup.** Each Opus 5.5 call reads about 33k tokens, nearly all of them from the cache. The tokens are the definitions of the 103 tools, 28 MCP servers, plugins and skills configured for this account, not the task. That is $0.20 per run for a 2-second workflow. Running with only the tools the task needs (for example `--strict-mcp-config` and a short `--tools` list) should cut both tokens and cost; untested.
5. **`claude` is not on the PBS job's `PATH`.** In job 7810470, all three Claude runs exited 127 ("command not found"). The binary is in `~/miniconda3/bin`, which interactive shells add to `PATH` but batch jobs do not. The script now calls it by full path.
6. **Unrestricted Claude Code was not used.** Starting Claude Code with `--dangerously-skip-permissions` was refused in this session. The runs use an allowlist instead, which caused the one denied call per run described under Results. The clio agent runs with `--autonomy yolo`. So the comparison is between Claude Code with narrow permissions and clio-coder with full ones.
7. **The compute node reaches the APIs only through the ALCF proxy.** The job exports `https_proxy` for Claude Code and sets `NODE_USE_ENV_PROXY=1` so Node-based clio-coder uses it too. `no_proxy` covers the local Ollama server.

## Reproduce

```bash
qsub ~/toam/polaris/perf_agents.pbs                       # NRUNS=5, AGENTS="claude alcf nemotron"
python3 ~/toam/polaris/summarize.py /eagle/radix-io/hyoklee/toam/agents_<jobid> /eagle/radix-io/hyoklee/toam/toam_agents.log
```

Needs: the Python venv `/eagle/radix-io/hyoklee/toam/venv` (`requirements.txt`); Claude Code logged in; clio-coder with an ALCF login (target `alcf-sophia`) and the `polaris-nemotron` target; Ollama and the Nemotron model on /eagle (see the polaris repo's `doc/20261022_claude_clio_coder_nemotron_polaris.md`).
