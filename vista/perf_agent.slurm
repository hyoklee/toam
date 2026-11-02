#!/bin/bash
#SBATCH -J toam-agent
#SBATCH -p gg
#SBATCH -N 1
#SBATCH --ntasks-per-node 1
#SBATCH --exclusive
#SBATCH -t 01:30:00
#SBATCH -A IBN22011
#SBATCH -o toam_agent_%j.log
# Has the clio agent (clio-coder, ALCF Sophia gpt-oss-120b) run the toam workflow
# on a Vista gg node, natively and with IOWARP=1 (clio-core runtime + POSIX adapter).
# NRUNS headless agent turns per mode. A `python` shim on PATH times every Python
# call the agent makes and, for IOWARP=1, preloads the adapter into Python only.
set -euo pipefail
NRUNS=${NRUNS:-3}
REPO=/work/11623/hyoklee/toam
PY=/work/11623/hyoklee/vista/toam-venv/bin/python
export MPLBACKEND=Agg
export CLIO_BUILD_DIR=/work/11623/hyoklee/vista/build/clio-core.cae-depends-on
HDF5_LIB=/work/11623/hyoklee/vista/opt/hdf5-current/lib64
OUT=$SCRATCH/toam-clio/agent_$SLURM_JOB_ID
mkdir -p $OUT
export CLIO_RUNTIME_LOG=$OUT/clio_runtime.log CLIO_PIDFILE=$OUT/clio_runtime.pid
echo "host=$(hostname) start=$(date -Is) core=$CLIO_BUILD_DIR toam=$(git -C $REPO log -1 --format=%h) clio-coder=$(clio-coder --version 2>&1 | head -1)"

TASK='Run the TOAM verification workflow in this directory: first run `python scripts/generate_data.py`, then run `python scripts/analysis.py`. Do not edit any file under scripts/. When both finish, report the baseline, TO-AB and TO-VT endurance limits written in docs/results.md.'

source /work/11623/hyoklee/vista/bin/clio_env.sh
CLIO_LD_LIBRARY_PATH=$HDF5_LIB:$LD_LIBRARY_PATH
unset LD_LIBRARY_PATH

# make_shim <dir> <iowarp 0|1>: `python`/`python3` that time each call into $dir/pycalls.txt
make_shim() {
  mkdir -p $1/bin
  cat > $1/bin/python <<SHIM
#!/bin/bash
s=\$(date +%s.%N)
if [ "$2" = 1 ]; then
  LD_LIBRARY_PATH="$CLIO_LD_LIBRARY_PATH" LD_PRELOAD="$CLIO_PRELOAD$CLIO_POSIX_LIB" $PY "\$@"
else
  $PY "\$@"
fi
rc=\$?
echo "PYCALL \$(echo "\$(date +%s.%N) - \$s" | bc) rc=\$rc args=\$*" >> $1/pycalls.txt
exit \$rc
SHIM
  chmod +x $1/bin/python && ln -sf python $1/bin/python3
}

# agent_run <mode> <i> <iowarp 0|1>
agent_run() {
  local W=$OUT/$1_$2
  mkdir -p $W/work && cp -r $REPO/scripts $W/work/
  make_shim $W $3
  local T0=$(date +%s.%N) rc=0
  PATH=$W/bin:$PATH timeout 900 clio-coder run --cwd $W/work --autonomy yolo --no-delegate \
    --timeout 840 --json-events terminal "$TASK" > $W/agent.jsonl 2> $W/agent.stderr || rc=$?
  local wall=$(echo "$(date +%s.%N) - $T0" | bc)
  local py=$(awk '{s+=$2} END {printf "%.2f", s}' $W/pycalls.txt 2>/dev/null || echo 0)
  local ncall=$(wc -l < $W/pycalls.txt 2>/dev/null || echo 0)
  local ok=no
  grep -q "TO‑AB corrected ≈  178.5" $W/work/docs/results.md 2>/dev/null && \
    grep -q "TO‑VT corrected ≈  193.9" $W/work/docs/results.md && ok=yes
  local edited=$(diff -rq $REPO/scripts $W/work/scripts > /dev/null && echo no || echo yes)
  echo "AGENT $1 run$2 wall=${wall}s rc=$rc python_calls=$ncall python_s=$py results_ok=$ok scripts_edited=$edited"
}

stop_runtime() { set +e; LD_LIBRARY_PATH=$CLIO_LD_LIBRARY_PATH eval "$CLIO_RUNTIME_STOP"; set -e; }
trap stop_runtime EXIT

for i in $(seq $NRUNS); do agent_run native $i 0; done

T0=$(date +%s.%N)
LD_LIBRARY_PATH=$CLIO_LD_LIBRARY_PATH LD_PRELOAD="$CLIO_PRELOAD" \
  $CLIO_BIN/clio_run runtime start > $CLIO_RUNTIME_LOG 2>&1 &
echo $! > $CLIO_PIDFILE
for i in $(seq 240); do grep -qa 'All .* pools created successfully' $CLIO_RUNTIME_LOG && break; sleep 0.25; done
grep -qa 'All .* pools created successfully' $CLIO_RUNTIME_LOG || { echo "IOWarp: runtime not ready"; exit 2; }
echo "IOWarp: runtime ready in $(echo "$(date +%s.%N) - $T0" | bc) s"

for i in $(seq $NRUNS); do agent_run iowarp1 $i 1; done
echo "end=$(date -Is)"
