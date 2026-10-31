#!/bin/bash
#SBATCH --job-name=toam_perf
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=/home/hyoklee/logs/toam_perf_%j.log
# Times the Vista toam workflow on Ares with the same protocol as docs/performance.md
# (5 iterations, per-script wall time), plus the Gemma and Claude workflows.
set -euo pipefail
ROOT=/mnt/common/hyoklee/toam_perf
PY=$ROOT/venv_pd/bin/python
export MPLBACKEND=Agg
echo "host=$(hostname) cpu=\"$(lscpu | sed -n 's/^Model name: *//p')\" cpus=$SLURM_CPUS_PER_TASK start=$(date -Is)"
$PY -c "import sys,numpy,pandas,matplotlib,scipy;print('python',sys.version.split()[0],'numpy',numpy.__version__,'pandas',pandas.__version__,'matplotlib',matplotlib.__version__,'scipy',scipy.__version__)"

# t <label> <cmd...>: run cmd, print wall seconds and max RSS
t() {
  local label=$1; shift
  /usr/bin/time -f "TIME $label %e s maxrss %M KB" "$@" > /dev/null 2>> $ROOT/stderr_$SLURM_JOB_ID.txt
  tail -1 $ROOT/stderr_$SLURM_JOB_ID.txt
}

for i in 1 2 3 4 5; do
  cd $ROOT/vista
  t "vista.generate_data it$i" $PY scripts/generate_data.py
  t "vista.analysis it$i" $PY scripts/analysis.py
done
for i in 1 2 3 4 5; do
  cd $ROOT/gemma
  t "gemma.gen_data it$i" $PY workflow/gen_data.py
  t "gemma.analyze it$i" $PY workflow/analyze.py
done
for i in 1 2 3 4 5; do
  cd $ROOT/claude/workflow
  t "claude.run_all it$i" $PY run_all.py
done
echo "end=$(date -Is)"
