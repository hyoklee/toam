#!/bin/bash
#SBATCH -J toam-iowarp
#SBATCH -p gg
#SBATCH -N 1
#SBATCH --ntasks-per-node 1
#SBATCH --exclusive
#SBATCH -t 00:20:00
#SBATCH -A IBN22011
#SBATCH -o toam_iowarp_%j.log
# Times the toam workflow on a Vista gg node natively and with IOWARP=1
# (clio-core runtime + LD_PRELOAD libclio_cte_posix.so), as in
# ares/perf_iowarp.sbatch. One untimed warm-up pass, then 5 iterations per mode
# in the order native, iowarp1, iowarp1, native, so neither mode always runs first.
set -euo pipefail
REPO=/work/11623/hyoklee/toam
PY=/work/11623/hyoklee/vista/toam-venv/bin/python
export MPLBACKEND=Agg
export CLIO_BUILD_DIR=/work/11623/hyoklee/vista/build/clio-core.cae-depends-on
HDF5_LIB=/work/11623/hyoklee/vista/opt/hdf5-current/lib64
OUT=$SCRATCH/toam-clio/iowarp_$SLURM_JOB_ID
mkdir -p $OUT
export CLIO_RUNTIME_LOG=$OUT/clio_runtime.log CLIO_PIDFILE=$OUT/clio_runtime.pid
echo "host=$(hostname) cpu=\"$(lscpu | sed -n 's/^Model name: *//p')\" start=$(date -Is) core=$CLIO_BUILD_DIR commit=$(git -C /work/11623/hyoklee/clio-core.cae-depends-on log -1 --format=%h) toam=$(git -C $REPO log -1 --format=%h)"
$PY -c "import sys,numpy,pandas,matplotlib;print('python',sys.version.split()[0],'numpy',numpy.__version__,'pandas',pandas.__version__,'matplotlib',matplotlib.__version__)"

t() {
  local label=$1; shift
  /usr/bin/time -f "TIME $label %e s maxrss %M KB" "$@" > /dev/null 2>> $OUT/stderr.txt
  tail -1 $OUT/stderr.txt
}

# run_all <mode> <block>: 5 timed iterations in a fresh copy of scripts/
run_all() {
  local mode=$1; local W=$OUT/$2
  mkdir -p $W && cp -r $REPO/scripts $W/
  for i in 1 2 3 4 5; do
    t "$mode generate_data it$i" $PY $W/scripts/generate_data.py
    t "$mode analysis it$i" $PY $W/scripts/analysis.py
  done
  rm -rf $W/scripts
}

source /work/11623/hyoklee/vista/bin/clio_env.sh
NATIVE_LD_LIBRARY_PATH=${LD_LIBRARY_PATH_ORIG:-}
CLIO_LD_LIBRARY_PATH=$HDF5_LIB:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$NATIVE_LD_LIBRARY_PATH

start_runtime() {
  local T0=$(date +%s.%N)
  LD_LIBRARY_PATH=$CLIO_LD_LIBRARY_PATH LD_PRELOAD="$CLIO_PRELOAD" \
    $CLIO_BIN/clio_run runtime start > $CLIO_RUNTIME_LOG 2>&1 &
  echo $! > $CLIO_PIDFILE
  for i in $(seq 240); do
    grep -qa 'All .* pools created successfully' $CLIO_RUNTIME_LOG && break
    kill -0 $(cat $CLIO_PIDFILE) 2>/dev/null || { echo "IOWarp: runtime exited early"; tail -20 $CLIO_RUNTIME_LOG; exit 2; }
    sleep 0.25
  done
  grep -qa 'All .* pools created successfully' $CLIO_RUNTIME_LOG || { echo "IOWarp: runtime not ready"; exit 2; }
  echo "IOWarp: runtime ready in $(echo "$(date +%s.%N) - $T0" | bc) s"
}
stop_runtime() { set +e; LD_LIBRARY_PATH=$CLIO_LD_LIBRARY_PATH eval "$CLIO_RUNTIME_STOP"; set -e; }
trap stop_runtime EXIT

# untimed warm-up so the first timed block does not pay for a cold page cache
mkdir -p $OUT/warm && cp -r $REPO/scripts $OUT/warm/ && $PY $OUT/warm/scripts/generate_data.py > /dev/null && $PY $OUT/warm/scripts/analysis.py > /dev/null

run_all native native_a

start_runtime
export LD_LIBRARY_PATH=$CLIO_LD_LIBRARY_PATH LD_PRELOAD="$CLIO_PRELOAD$CLIO_POSIX_LIB"
echo "IOWarp ON: adapter=$CLIO_POSIX_LIB"
$PY -c "print('adapter mapped:', any('libclio_cte_posix' in l for l in open('/proc/self/maps')))"
run_all iowarp1 iowarp1_a
run_all iowarp1 iowarp1_b
unset LD_PRELOAD; export LD_LIBRARY_PATH=$NATIVE_LD_LIBRARY_PATH

run_all native native_b

for b in iowarp1_a iowarp1_b native_b; do
  if diff -rq $OUT/native_a $OUT/$b > /dev/null; then echo "outputs native_a vs $b: identical"
  else echo "outputs native_a vs $b: DIFFER"; diff -rq $OUT/native_a $OUT/$b | head -5 || true; fi
done
echo "end=$(date -Is)"
