#!/usr/bin/env bash
# Run shipped EESSI GROMACS builds whose SVE vector length is fixed at build
# time (neoverse_v1: 256 bit, a64fx: 512 bit, grace: 128 bit) on this 128-bit
# host, natively and under qemu-aarch64 user mode with the vector length of the
# target. A short MD run of a water box is the test.
set -uo pipefail
work=${WORK:-$PWD/sve-vl}
mkdir -p "$work"
qemu=$(command -v qemu-aarch64 || command -v qemu-aarch64-static)
echo "qemu: $qemu ($($qemu --version | head -1))"
gmxdir() { ls -d /cvmfs/software.eessi.io/versions/2025.06/software/linux/aarch64/$1/software/GROMACS/2025.2-foss-2025a; }
run() { # label tree prefix...
  local label=$1 tree=$2; shift 2
  local d; d=$(gmxdir "$tree") || { echo "RESULT $label: no GROMACS in $tree"; return; }
  local w="$work/$label"; mkdir -p "$w"; cd "$w"
  (
    set +u
    export EESSI_SOFTWARE_SUBDIR_OVERRIDE=aarch64/$tree
    source /cvmfs/software.eessi.io/versions/2025.06/init/bash >/dev/null 2>&1
    module load GROMACS/2025.2-foss-2025a >/dev/null 2>&1 || { echo "RESULT $label: module load failed"; exit 0; }
    gmx=$(command -v gmx_mpi || command -v gmx)
    "$gmx" -quiet solvate -cs spc216 -box 2.5 2.5 2.5 -o conf.gro > prep.log 2>&1
    n=$(( ($(sed -n 2p conf.gro) ) / 3 ))
    printf '#include "oplsaa.ff/forcefield.itp"\n#include "oplsaa.ff/spc.itp"\n[ system ]\nwater\n[ molecules ]\nSOL %s\n' "$n" > topol.top
    printf 'integrator=md\nnsteps=500\ndt=0.002\ncutoff-scheme=Verlet\nrcoulomb=1.0\nrvdw=1.0\ncoulombtype=PME\nconstraints=h-bonds\ntcoupl=v-rescale\ntc-grps=System\ntau-t=0.1\nref-t=300\n' > md.mdp
    "$gmx" -quiet grompp -f md.mdp -c conf.gro -p topol.top -o md.tpr -maxwarn 2 >> prep.log 2>&1 || { echo "RESULT $label: grompp failed"; tail -5 prep.log; exit 0; }
    s=$(date +%s)
    "$@" "$gmx" -quiet mdrun -s md.tpr -ntomp 2 -nb cpu -g md.log > run.log 2>&1
    rc=$?
    e=$(( $(date +%s) - s ))
    simd=$(grep -m1 -E "SIMD instructions" md.log 2>/dev/null | sed 's/  */ /g')
    perf=$(grep -m1 "^Performance:" md.log 2>/dev/null | awk '{print $2 " ns/day"}')
    echo "RESULT $label: rc=$rc ${e}s ${simd:-no md.log} ${perf}"
    [ $rc -ne 0 ] && tail -6 run.log | sed 's/^/    /'
    true
  )
  cd - >/dev/null
}
run grace-native nvidia/grace
run v1-native neoverse_v1
run v1-qemu-vl256 neoverse_v1 "$qemu" -cpu max,sve-default-vector-length=32
run v1-qemu-vl128 neoverse_v1 "$qemu" -cpu max,sve-default-vector-length=16
run a64fx-native a64fx
run a64fx-qemu-vl512 a64fx "$qemu" -cpu max,sve-default-vector-length=64
run grace-qemu-vl128 nvidia/grace "$qemu" -cpu max,sve-default-vector-length=16
