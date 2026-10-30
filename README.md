# TOAM – Topology‑Optimized Additive Manufacturing Wiki

This repository contains a lightweight, reproducible workflow that verifies the key findings of the paper **“Fatigue Response of a Topology Optimized Feature‑based Component”** (Carr et al., *Engineering Failure Analysis*, Jan 2026).

## What is covered
- A synthetic data generator that reproduces the Basquin fatigue curves for the baseline dog‑bone, TO‑as‑built (TO‑AB) and TO‑vibratory‑tumbled (TO‑VT) specimens using the coefficients reported in Table 3 of the paper.
- A simple defect‑model script that evaluates the El‑Haddad/Murakami surface‑roughness and pore‑size contributions described in Sections 5.2‑5.3.
- Plots that compare the simulated results with the experimental data (Figures 5, 11, 12, 13).
- A Markdown‑based wiki (`docs/`) that documents the methodology, results, and a verification summary.

## Repository layout
```
/README.md               – this overview
/workflow.yaml            – the executable workflow description
/scripts/                – Python scripts
    generate_data.py      – creates synthetic fatigue data
    analysis.py          – runs the defect model and makes plots
/data/                    – generated CSV files (committed after the run)
/docs/                    – wiki pages (abstract, methodology, results …)
```

The workflow can be executed on the remote compute host **Ares** (see `workflow.yaml`). After the run finishes the generated CSV files, PNG plots and the updated wiki pages are committed back to the repository.

---
*Prepared by the CLIO assistant for the Engineering Failure Analysis submission.*