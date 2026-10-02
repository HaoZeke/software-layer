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
load() { # tree: print the gmx path after loading that tree's GROMACS
  set +u
  export EESSI_SOFTWARE_SUBDIR_OVERRIDE=aarch64/$1
  source /cvmfs/software.eessi.io/versions/2025.06/init/bash >/dev/null 2>&1
  module load GROMACS/2025.2-foss-2025a >/dev/null 2>&1 || return 1
  command -v gmx_mpi || command -v gmx
}
# One portable run input, prepared with the build that runs natively here.
prep() (
  gmx=$(load nvidia/grace) || { echo "prep: module load failed"; exit 1; }
  cd "$work"
  "$gmx" -quiet solvate -cs spc216 -box 2.5 2.5 2.5 -o conf.gro > prep.log 2>&1
  n=$(( $(sed -n 2p conf.gro) / 3 ))
  printf '#include "oplsaa.ff/forcefield.itp"\n#include "oplsaa.ff/spc.itp"\n[ system ]\nwater\n[ molecules ]\nSOL %s\n' "$n" > topol.top
  printf 'integrator=md\nnsteps=500\ndt=0.002\ncutoff-scheme=Verlet\nrcoulomb=1.0\nrvdw=1.0\ncoulombtype=PME\nconstraints=h-bonds\ntcoupl=v-rescale\ntc-grps=System\ntau-t=0.1\nref-t=300\n' > md.mdp
  "$gmx" -quiet grompp -f md.mdp -c conf.gro -p topol.top -o md.tpr -maxwarn 2 >> prep.log 2>&1
)
run() ( # label tree prefix...
  label=$1 tree=$2; shift 2
  gmx=$(load "$tree") || { echo "RESULT $label: module load failed"; exit 0; }
  w="$work/$label"; mkdir -p "$w"; cd "$w"
  s=$(date +%s)
  "$@" "$gmx" -quiet mdrun -s "$work/md.tpr" -ntomp 2 -nb cpu -g md.log > run.log 2>&1
  rc=$?
  e=$(( $(date +%s) - s ))
  simd=$(grep -m1 -E "SIMD instructions" md.log 2>/dev/null | sed 's/  */ /g')
  perf=$(grep -m1 "^Performance:" md.log 2>/dev/null | awk '{print $2 " ns/day"}')
  echo "RESULT $label: rc=$rc ${e}s ${simd:-no md.log} ${perf}"
  [ $rc -ne 0 ] && tail -6 run.log | sed 's/^/    /'
  true
)
prep || { echo "RESULT prep failed"; tail -20 "$work/prep.log"; exit 1; }
run grace-native nvidia/grace
run v1-native neoverse_v1
run v1-qemu-vl256 neoverse_v1 "$qemu" -cpu max,sve-default-vector-length=32
run v1-qemu-vl128 neoverse_v1 "$qemu" -cpu max,sve-default-vector-length=16
run a64fx-native a64fx
run a64fx-qemu-vl512 a64fx "$qemu" -cpu max,sve-default-vector-length=64
run grace-qemu-vl128 nvidia/grace "$qemu" -cpu max,sve-default-vector-length=16
# The same builds under QEMU's named models of the target cores, which carry
# those cores' ID registers and feature sets rather than every feature (max).
run v1-qemu-neoverse-v1 neoverse_v1 "$qemu" -cpu neoverse-v1,sve-default-vector-length=32
run a64fx-qemu-a64fx a64fx "$qemu" -cpu a64fx,sve-default-vector-length=64
