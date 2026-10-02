#!/usr/bin/env bash
# Resolve -mcpu=native under each recorded /proc/cpuinfo view and compare the
# result with the references of EESSI/software-layer-scripts#311, using the
# same extraction as its check_native_flags.sh (cc1 -m* options for GCC;
# target-cpu, tune-cpu, target-abi and target-feature for clang).
# Uses sudo for the bind mount (CI runner).
set -uo pipefail
A=$(dirname "$(readlink -f "$0")")
out=${OUT:-$PWD/native-refs}
mkdir -p "$out"
gcc_flags() { "$1" -mcpu=native -### -E - < /dev/null 2>&1 | awk '$1 ~ /\/cc1$/' | tr -d '"' | tr -s ' ' '\n' | grep '^-m'; }
clang_flags() { "$1" -mcpu=native -### -c -x c - -o /dev/null < /dev/null 2>&1 | grep '"-cc1"' | tr -d '"' | tr -s ' ' '\n' \
  | awk '/^-(target-cpu|tune-cpu|target-abi|target-feature)$/ { opt=$0; getline; print opt " " $0 }'; }
# view -> EESSI target whose references apply (none: no reference exists)
declare -A target=(
  [neoverse_v1-rhel8]=neoverse_v1 [neoverse_v1-amazon]=neoverse_v1
  [v2-graviton4like]=aws/graviton4 [v2-graviton4like-nopac]=aws/graviton4
  [v2-grace-rhel9]=nvidia/grace [v2-grace-ubuntu2204]=nvidia/grace [v2-axion]=none [a64fx-rocky8]=none
  [v2-grace-rhel9-asbuilt]=nvidia/grace [v2-grace-ubuntu2204-asbuilt]=nvidia/grace
  [v2-axion-as-grace]=nvidia/grace [v2-axion-as-graviton4]=aws/graviton4 [v2-graviton4like-asbuilt]=aws/graviton4 )
# shipped/<target>/<compiler>.txt: the -mcpu GCC recorded in DW_AT_producer of
# the shipped EESSI tree, i.e. what the real build hosts resolved.
# EESSI version, module, compiler binary, reference name
compilers=(
  "2025.06 GCCcore/13.3.0 gcc gcc-13.3.0"
  "2025.06 GCCcore/14.2.0 gcc gcc-14.2.0"
  "2025.06 GCCcore/14.3.0 gcc gcc-14.3.0"
  "2026.06 GCCcore/15.2.0 gcc gcc-15.2.0"
  "2025.06 LLVM/20.1.8-GCCcore-14.3.0 clang clang-20.1.8"
  "2026.06 LLVM/21.1.8-GCCcore-15.2.0 clang clang-21.1.8" )
for c in "${compilers[@]}"; do
  read -r ver mod bin ref <<<"$c"
  path=$(set +u; export EESSI_SOFTWARE_SUBDIR_OVERRIDE=aarch64/neoverse_n1
         source /cvmfs/software.eessi.io/versions/$ver/init/bash >/dev/null 2>&1
         module load "$mod" >/dev/null 2>&1 && command -v "$bin")
  [ -z "$path" ] && { echo "MISSING $ver $mod"; continue; }
  for v in $(printf '%s\n' "${!target[@]}" | sort); do
    sudo mount --bind "$A/cpuinfo/$v" /proc/cpuinfo
    if [ "$bin" = gcc ]; then gcc_flags "$path"; else clang_flags "$path"; fi > "$out/$v.$ref.txt"
    sudo umount /proc/cpuinfo
    # The same view without a mount: GCC (9+) reads GCC_CPUINFO and LLVM (20+)
    # reads LLVM_CPUINFO in place of /proc/cpuinfo.
    if [ "$bin" = gcc ]; then GCC_CPUINFO="$A/cpuinfo/$v" gcc_flags "$path"; else LLVM_CPUINFO="$A/cpuinfo/$v" clang_flags "$path"; fi > "$out/$v.$ref.env.txt"
    if cmp -s "$out/$v.$ref.txt" "$out/$v.$ref.env.txt"; then echo "ENVSAME $v $ref"; else echo "ENVDIFF $v $ref: $(diff "$out/$v.$ref.txt" "$out/$v.$ref.env.txt" | grep '^[<>]' | tr '\n' ' ')"; fi
    t=${target[$v]}
    for kind in refs311 shipped; do
      r="$A/$kind/$t/$ref.txt"
      [ "$t" != none ] && [ -f "$r" ] || continue
      if [ "$kind" = shipped ]; then mine=$(grep -- '-mcpu=' "$out/$v.$ref.txt"); else mine=$(cat "$out/$v.$ref.txt"); fi
      if d=$(diff <(grep -v '^#' "$r") <(echo "$mine")); then
        echo "MATCH  $v $ref ($kind $t)"
      else
        echo "DIFFER $v $ref ($kind $t): $(echo "$d" | grep '^[<>]' | tr '\n' ' ')"
      fi
      seen=1
    done
    [ -n "${seen:-}" ] || echo "NOREF  $v $ref: $(grep -E 'mcpu=|target-cpu' "$out/$v.$ref.txt" | tr '\n' ' ')"
    unset seen
  done
done
