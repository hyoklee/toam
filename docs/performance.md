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

No Ares timings are available yet for comparison.
