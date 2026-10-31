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

**These numbers measure speed, not correctness.** `analysis.py` sets El Haddad's `area0` to a placeholder (`baseline**2/100`), not Eq. 4. Its TO-AB and TO-VT values (200.2 and 222.1 MPa) are therefore not Eq. 3 predictions. With Eq. 3–4 (√area0 = 448 µm), the roughness predictions are 178.5 MPa for TO-AB and 193.9 MPa for TO-VT.
