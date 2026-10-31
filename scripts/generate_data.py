#!/usr/bin/env python3
"""Synthetic fatigue data generator for the TOAM verification workflow.
Produces CSV files for three specimen categories (dogbone, TO‑AB, TO‑VT)
matching the Basquin parameters reported in Table 3 of the paper.
"""
import numpy as np, pandas as pd, os, json

# Basquin coefficients (A, B) from Table 3 – stress range Δσ = A * N_f^B
BASES = {
    "dogbone": {"A": 7160.0, "B": -0.175},
    "TO_AB":   {"A": 2394.0, "B": -0.141},
    "TO_VT":   {"A": 1280.0, "B": -0.0845},
}

# Cycle range (log‑space) – typical high‑cycle fatigue regime
cycles = np.logspace(3, 7, num=50)  # 1e3 … 1e7 cycles

out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
os.makedirs(out_dir, exist_ok=True)

for name, coeff in BASES.items():
    A, B = coeff["A"], coeff["B"]
    # deterministic Basquin curve
    stress = A * cycles ** B
    # add modest log‑normal scatter (≈10 % sigma) to mimic experimental variability
    rng = np.random.default_rng(seed=42)
    scatter = rng.lognormal(mean=0.0, sigma=0.1, size=stress.shape)
    stress_scattered = stress * scatter
    df = pd.DataFrame({"cycles": cycles, "stress_range": stress_scattered})
    csv_path = os.path.join(out_dir, f"{name}.csv")
    df.to_csv(csv_path, index=False)
    print(f"Wrote {csv_path}")

# Optional: save a small JSON manifest describing the generated files
manifest = {"files": [f"{name}.csv" for name in BASES]}
with open(os.path.join(out_dir, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)
