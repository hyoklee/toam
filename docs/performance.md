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
