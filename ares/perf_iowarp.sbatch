#!/bin/bash
#SBATCH --job-name=toam_iowarp
#SBATCH --partition=compute
#SBATCH --nodelist=ares-comp-10
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=/home/hyoklee/logs/toam_iowarp_%j.log
# Times the three toam workflows (Vista/clio-agent, Gemma, Claude Code) natively and
# with IOWARP=1 (clio-core runtime + LD_PRELOAD libclio_cte_posix.so), as in
# ~/bin/run_case7_dev.sbatch. Same node, same job, 5 iterations per mode.
set -euo pipefail
ROOT=/mnt/common/hyoklee/toam_perf
PY=$ROOT/venv_pd/bin/python
CONDA_PREFIX=/home/hyoklee/mc3/envs/miv
CORE_INSTALL=/home/hyoklee/core_dev_miv_1020/install
CORE=$CORE_INSTALL/lib/libclio_cte_posix.so
export CLIO_SERVER_CONF=/home/hyoklee/bin/chimaera_case7.yaml
export MPLBACKEND=Agg
OUT=$ROOT/iowarp_$SLURM_JOB_ID
mkdir -p $OUT
echo "host=$(hostname) cpu=\"$(lscpu | sed -n 's/^Model name: *//p')\" start=$(date -Is) core=$CORE"

t() {
  local label=$1; shift
  /usr/bin/time -f "TIME $label %e s maxrss %M KB" "$@" > /dev/null 2>> $OUT/stderr.txt
  tail -1 $OUT/stderr.txt
}

run_all() {
  local mode=$1
  for i in 1 2 3 4 5; do
    cd $ROOT/vista
    t "$mode vista.generate_data it$i" $PY scripts/generate_data.py
    t "$mode vista.analysis it$i" $PY scripts/analysis.py
  done
  for i in 1 2 3 4 5; do
    cd $ROOT/gemma
    t "$mode gemma.gen_data it$i" $PY workflow/gen_data.py
    t "$mode gemma.analyze it$i" $PY workflow/analyze.py
  done
  for i in 1 2 3 4 5; do
    cd $ROOT/claude/workflow
    t "$mode claude.run_all it$i" $PY run_all.py
  done
  # keep this mode's outputs for an identity check
  mkdir -p $OUT/$mode
  cp -r $ROOT/vista/toam_repo $OUT/$mode/vista
  cp -r $ROOT/gemma/results $OUT/$mode/gemma
  cp -r $ROOT/claude/results $OUT/$mode/claude
}

run_all native

# --- IOWARP=1: start the clio-core runtime, then preload the POSIX adapter ---
T0=$(date +%s.%N)
( export PATH="$CORE_INSTALL/bin:$PATH" LD_LIBRARY_PATH="$CORE_INSTALL/lib"
  clio_run start ) > $OUT/clio_runtime.log 2>&1 &
CLIO_BG=$!
stop_runtime() {
  ( export PATH="$CORE_INSTALL/bin:$PATH" LD_LIBRARY_PATH="$CORE_INSTALL/lib"
    clio_run stop ) >> $OUT/clio_runtime.log 2>&1 || true
}
trap stop_runtime EXIT
for i in $(seq 1 120); do
  grep -qa 'All .* pools created successfully' $OUT/clio_runtime.log && break
  kill -0 $CLIO_BG 2>/dev/null || { echo "IOWarp: runtime exited early"; tail -20 $OUT/clio_runtime.log; exit 2; }
  sleep 1
done
grep -qa 'All .* pools created successfully' $OUT/clio_runtime.log || { echo "IOWarp: runtime not ready"; exit 2; }
sleep 2
echo "IOWarp: runtime ready in $(echo "$(date +%s.%N) - $T0" | bc) s"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$CORE_INSTALL/lib"
export LD_PRELOAD="$CORE"
echo "IOWarp ON: adapter=$CORE"
$PY -c "print('adapter mapped:', any('libclio_cte_posix' in l for l in open('/proc/self/maps')))"

run_all iowarp1
unset LD_PRELOAD

for w in vista gemma claude; do
  if diff -rq $OUT/native/$w $OUT/iowarp1/$w > /dev/null; then echo "outputs $w: identical"
  else echo "outputs $w: DIFFER"; diff -rq $OUT/native/$w $OUT/iowarp1/$w | head -5 || true; fi
done
echo "end=$(date -Is)"
