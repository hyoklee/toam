# Workflow Performance

Run on TACC Vista, `gg` partition (Grace CPU node `i617-092`), Slurm job 1111429,
Python 3.13, numpy 2.5.4, pandas 3.1.0, matplotlib 3.11.2.

| Iteration | generate_data.py (s) | analysis.py (s) | Total (s) |
|---|---|---|---|
| 1 (cold) | 2.20 | 2.22 | 4.42 |
| 2 | 0.54 | 1.15 | 1.69 |
| 3 | 0.43 | 0.95 | 1.38 |
| 4 | 0.33 | 0.94 | 1.28 |
| 5 | 0.33 | 0.94 | 1.27 |

Slurm job elapsed time: 19 s (includes job startup).
Runtime is dominated by interpreter startup and pandas/matplotlib imports.

## Ares

Run on Ares, `compute` partition (node `ares-comp-10`, 2× Intel Xeon Silver 4114 @ 2.20 GHz,
16 CPUs, `--exclusive`), Slurm job 25308, Python 3.12.13, numpy 2.4.6, pandas 3.1.0,
matplotlib 3.10.9. Same protocol: 5 iterations of `generate_data.py` then `analysis.py`,
timed with `/usr/bin/time` ([`ares/perf.sbatch`](../ares/perf.sbatch), log
[`ares/toam_perf_25308.log`](../ares/toam_perf_25308.log)).

| Iteration | generate_data.py (s) | analysis.py (s) | Total (s) | max RSS (MB) |
|---|---|---|---|---|
| 1 | 0.91 | 2.87 | 3.78 | 108 |
| 2 | 0.89 | 2.70 | 3.59 | 108 |
| 3 | 0.84 | 2.72 | 3.56 | 108 |
| 4 | 0.92 | 2.66 | 3.58 | 108 |
| 5 | 0.89 | 2.78 | 3.67 | 107 |

Slurm accounting is disabled on Ares, so there is no job elapsed time. The 10 timed runs add up to 18.2 s.

## Vista vs Ares

| | Vista (Grace, job 1111429) | Ares (Xeon 4114, job 25308) | Ares / Vista |
|---|---|---|---|
| iteration 1 total | 4.42 s | 3.78 s | 0.86× |
| steady state (iterations 4–5 mean) | 1.28 s | 3.63 s | **2.8×** |
| generate_data.py, steady | 0.33 s | 0.91 s | 2.8× |
| analysis.py, steady | 0.94 s | 2.72 s | 2.9× |

- **Same output on both machines.** The data CSVs match to ≤3.5×10⁻¹⁶ relative (last-digit rounding). `docs/results.md` is identical: baseline 429.4, TO-AB 200.2 and TO-VT 222.1 MPa.
- **Warm runs are about 2.8× faster on Vista.** At steady state, Vista's Grace core is about 2.8× faster than Ares's 2017 Xeon Silver 4114 at 2.2 GHz. Both runs are dominated by interpreter start-up and pandas/matplotlib imports, so this mostly measures import and single-thread speed.
- **The first iteration is not slower on Ares.** Ares's first run is only 6% slower than its later ones, while Vista's is 3.5× slower. On Ares the environment was already in the page cache from installing it just before the job. Vista's iteration 1 includes cold-cache imports.
- **Other toam workflows on the same Ares node,** 5 iterations each:

| workflow | steady time per run | max RSS | what it computes |
|---|---|---|---|
| this repo (clio agent) | 3.63 s | 108 MB | Basquin curves from Table 3 and an El Haddad correction |
| Gemma 4 31B clio agent (`gen_data.py` + `analyze.py`) | 3.58 s | 104 MB | RO, Basquin, pores, El Haddad, Fatemi-Socie (FS hard-coded) |
| Claude Code rewrite (`run_all.py`, 16 processes) | 8.28 s | 151 MB | Same five checks, plus a 4000-campaign Basquin Monte Carlo and a 0.5° Fatemi-Socie plane scan |

**These numbers measure speed, not correctness.** They were taken with an earlier `analysis.py` that set El Haddad's `area0` to a placeholder (`baseline**2/100`) and reported 200.2 MPa (TO-AB) and 222.1 MPa (TO-VT). `analysis.py` now applies Eq. 3–4 (√area0 = 448 µm, baseline from the Table 3 Basquin fit at 10⁷ cycles = 426.5 MPa) and reports 178.5 MPa (TO-AB) and 193.9 MPa (TO-VT).

## clio-core (IOWARP=1) on Ares

**Question:** did clio-core help when the clio agent with Gemma ran this experiment?

**Answer: no.** The agents' runs never turned clio-core on. Turning it on by hand (`IOWARP=1`) changes neither the timings nor the outputs of any of the three workflows. It costs 4.1 s to start the runtime and about 3 MB more memory per process.

- **The agent runs never used clio-core.** Gemma's job script (`toam_gemma/ares/run_toam.sbatch`) and the agents' Ares jobs (25151, 25165, 25178, 25307) run plain `python` with no IOWarp runtime and no adapter. In the clio agent session ledgers, the only clio capability called is the task board (`gateway` → `tasks`), and no clio-core runs were recorded (`runIds: []`).
- **Setup for this test.** Ares job 25309, on `ares-comp-10` (`--exclusive`), is the same node as job 25308. In one job, all three workflows ran 5 times natively, then 5 times with `IOWARP=1`. `IOWARP=1` follows `~/bin/run_case7_dev.sbatch`:
  - start `clio_run` with the RAM-tier config `chimaera_case7.yaml`;
  - wait for "All pools created";
  - then `LD_PRELOAD=core_dev_miv_1020/install/lib/libclio_cte_posix.so`, the same clio-core build as the MiV case 7 runs.

  The adapter was confirmed mapped into the Python process ([`ares/perf_iowarp.sbatch`](../ares/perf_iowarp.sbatch), log [`ares/toam_iowarp_25309.log`](../ares/toam_iowarp_25309.log)).

| workflow | native, iteration 1 | native, iterations 2–5 | IOWARP=1, iteration 1 | IOWARP=1, iterations 2–5 | change (2–5) | max RSS |
|---|---|---|---|---|---|---|
| this repo (clio agent, gpt-oss) | 4.38 s | 3.57 s | 3.54 s | 3.52 s | −1.3% | 107 → 110 MB |
| Gemma 4 31B clio agent | 4.36 s | 3.51 s | 3.54 s | 3.62 s | +3.2% | 103 → 106 MB |
| Claude Code rewrite (16 processes) | 8.53 s | 8.34 s | 8.45 s | 8.37 s | +0.4% | 151 → 154 MB |

Per script, iterations 2–5, with the standard deviation across iterations:

| script | native | IOWARP=1 | change |
|---|---|---|---|
| `generate_data.py` (this repo) | 0.88 ± 0.06 s | 0.86 ± 0.02 s | −2.3% |
| `analysis.py` (this repo) | 2.69 ± 0.03 s | 2.66 ± 0.04 s | −1.0% |
| `gen_data.py` (Gemma) | 1.29 ± 0.04 s | 1.34 ± 0.03 s | +3.9% |
| `analyze.py` (Gemma) | 2.22 ± 0.08 s | 2.28 ± 0.07 s | +2.8% |
| `run_all.py` (Claude Code) | 8.34 ± 0.10 s | 8.37 ± 0.07 s | +0.4% |

- **The differences are noise.** All changes are within ±4%, which is about 1–2 standard deviations, and they go in both directions. The iteration-1 times look faster with `IOWARP=1` only because the native block ran first, when Python's files were not yet in the page cache. The `IOWARP=1` block ran second, with everything already cached.
- **The outputs are identical.** All files match between modes. The one exception is the `elapsed_s` field that `run_all.py` writes into its own `summary.json`.
- **Overhead.** Starting the runtime took **4.1 s**. That is longer than one whole run of either agent workflow, so with `IOWARP=1` every job is slower overall. The preloaded adapter adds about 3 MB of resident memory to each process.
- **Why nothing changes.**
  - The POSIX adapter only routes paths that contain a `clio::` component. These workflows write plain paths, so the adapter intercepts calls and passes them all through.
  - The I/O is tiny: a few KB of CSV, JSON and text plus a few PNGs per run.
  - Run time is dominated by Python start-up, imports and numerics (see above).
  - Even with `clio::` paths, there would be at most a few milliseconds of I/O to speed up.
- **What did shape Gemma's result.** The model and clio-coder's agent loop did, not clio-core:
  - Its task-board calls were malformed and stalled the first turn.
  - The context engine evicted and compacted the conversation late (27.1k → 12k tokens), because the ALCF context window is unknown to clio-coder.

## clio agent and clio-core (IOWARP=1) on Vista

**Question:** how does the workflow perform on a Vista compute node when the clio agent runs it, with and without clio-core?

**Answer:** clio-core changes neither the results nor the agent's time in any way we can measure. On its own it makes each Python run about 0.1 s (8%) slower, from loading its libraries. When the agent runs the workflow, about 90% of each run is the agent and the LLM, so that difference disappears in the noise. Every run, agent or not, produced identical outputs (178.5 MPa TO-AB, 193.9 MPa TO-VT).

**Setup.** Vista `gg` partition (Grace Neoverse-V2 CPU node, `--exclusive`), toam commit `e3136ee`, Python 3.13.13, numpy 2.5.4, pandas 3.1.0, matplotlib 3.11.2.

- **clio-core:** build `clio-core.cae-depends-on` (commit `e7277f40`), the only Vista build without a CUDA dependency (`gg` nodes have no `libcuda.so.1`). The runtime is configured as in `vista/bin/clio_env.sh` with the single-node RAM-tier config `chimaera_case6.yaml`; the adapter is `LD_PRELOAD=libclio_cte_posix.so`. That build's original HDF5 install was deleted, so `hdf5-current` (same `libhdf5.so.1000` soname) is put on `LD_LIBRARY_PATH`. Only the assimilation engine uses HDF5; the POSIX adapter path does not.
- **clio agent:** `clio-coder run` 0.6.4, headless, `--autonomy yolo --no-delegate`, target ALCF Sophia `openai/gpt-oss-120b`. Each run starts in a fresh copy of `scripts/` and is asked to run `generate_data.py`, then `analysis.py`, without editing `scripts/`, and to report the three endurance limits. A `python` shim on `PATH` times every Python call the agent makes. With `IOWARP=1` it preloads the adapter into Python only, as on Ares; the agent process itself is not preloaded.

### Workflow alone (job 1111711)

[`vista/perf_iowarp.slurm`](../vista/perf_iowarp.slurm), log [`vista/toam_iowarp_1111711.log`](../vista/toam_iowarp_1111711.log). There is one untimed warm-up pass, then 5 iterations per block in the order native, IOWARP=1, IOWARP=1, native, so neither mode always runs on the coldest cache. The committed script drops one extra warm-up loop that the job ran, which rewrote the same deterministic CSVs inside the repo.

| block | per-run total, iterations 1–5 | mean |
|---|---|---|
| native (first) | 1.25, 1.26, 1.26, 1.24, 1.25 s | 1.25 s |
| IOWARP=1 | 1.44, 1.36, 1.33, 1.28, 1.30 s | 1.34 s |
| IOWARP=1 | 1.35, 1.35, 1.30, 1.35, 1.32 s | 1.33 s |
| native (last) | 1.25, 1.25, 1.22, 1.20, 1.19 s | 1.22 s |

| script | native (10 runs) | IOWARP=1 (10 runs) | change |
|---|---|---|---|
| `generate_data.py` | 0.329 ± 0.011 s | 0.393 ± 0.029 s | +19.5% |
| `analysis.py` | 0.908 ± 0.017 s | 0.945 ± 0.026 s | +4.1% |
| both | 1.237 ± 0.025 s | 1.338 ± 0.045 s | **+8.2%** |

- **Starting the runtime took 0.78 s** (1.78 s in the agent job), compared with 4.1 s on Ares.
- **The slowdown is real but small,** about 0.1 s per run. Both IOWARP=1 blocks are slower than both native blocks. The cost is fixed per process (loading the preloaded clio libraries and connecting to the runtime), which is why it shows up most in the shorter `generate_data.py`. Max RSS rises by about 18 MB (median 81 → 99 MB; the 64 KB kernel pages make RSS coarse).
- **The outputs are identical** across all four blocks.
- **A cold page cache matters more than clio-core.** An earlier job without the warm-up (1111707) ran native first and made IOWARP=1 look 11% *faster*. That was only page-cache warm-up in the first native block, the same effect seen on Ares.

### clio agent running the workflow (job 1112674)

[`vista/perf_agent.slurm`](../vista/perf_agent.slurm), log [`vista/toam_agent_1112674.log`](../vista/toam_agent_1112674.log), per-run agent output and Python-call timings in [`vista/agent_1112674/`](../vista/agent_1112674/). Three agent runs native, then the runtime is started, then three agent runs with IOWARP=1.

| run | wall time | agent turn | Python (workflow) | LLM + agent loop | LLM calls | input / output tokens |
|---|---|---|---|---|---|---|
| native 1 (cold) | 33.8 s | 23.6 s | 9.66 s | 14.0 s | 3 | 15,795 / 141 |
| native 2 | 12.9 s | 9.3 s | 1.65 s | 7.7 s | 3 | 15,779 / 154 |
| native 3 | 12.4 s | 8.6 s | 1.30 s | 7.3 s | 3 | 15,795 / 139 |
| IOWARP=1 1 | 11.8 s | 8.0 s | 1.51 s | 6.5 s | 3 | 15,822 / 147 |
| IOWARP=1 2 | 12.3 s | 8.8 s | 1.31 s | 7.5 s | 3 | 15,824 / 258 |
| IOWARP=1 3 | 13.7 s | 9.9 s | 1.21 s | 8.7 s | 4 | 21,346 / 174 |

*Wall time* is the whole `clio-coder run`, including its start-up of about 3.5–4 s. *Agent turn* is the turn's start and end times as clio-coder reports them. *LLM + agent loop* is agent turn minus Python time.

- **All 6 agent runs succeeded.** Each ran exactly `generate_data.py` then `analysis.py`, left `scripts/` untouched, produced the correct `docs/results.md`, and reported 426.5 / 178.5 / 193.9 MPa. One IOWARP=1 run made one extra command and LLM call before answering.
- **The agent dominates.** In a warm run, the workflow's Python is about 1.3 s of a 12–13 s run (about 10%). The rest is clio-coder start-up (about 4 s) and three ALCF round trips with about 16k input tokens each (about 7–8 s).
- **No measurable clio-core effect on agent runs.** Warm native runs average 12.7 s and IOWARP=1 runs 12.6 s. Run-to-run LLM latency varies by ±1 s, which is ten times the 0.1 s that clio-core costs the workflow itself.
- **The first run is cold.** Native run 1 took 33.8 s: the Python environment and clio-coder's Node runtime were loaded from disk for the first time in the job, and Python alone took 9.7 s instead of 1.3 s.
- **Why clio-core can't help here.** As on Ares, the workflow writes plain paths, so the adapter intercepts calls and passes them all through. Only `clio::` paths go through clio-core. There are only a few KB of CSV, text and PNG output per run to speed up anyway.
