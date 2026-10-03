#!/usr/bin/env bash
# Generate each target's /proc/cpuinfo view from its recorded -mcpu string with
# gen_armprofile.py and that GCC version's own tables, then check that the GCC
# driver, reading the view through GCC_CPUINFO, gives the same string back.
set -uo pipefail
A=$(dirname "$(readlink -f "$0")")
W=${WORK:-$PWD/gen-check}
mkdir -p "$W"
# EESSI version, GCCcore module, GCC branch, target, recorded string
checks=(
  "2025.06 GCCcore/14.3.0 gcc-14 grace -mcpu=neoverse-v2+crc+sve2-aes+sve2-sha3+sve2-sm4+norng+nossbs+nopauth"
  "2025.06 GCCcore/14.3.0 gcc-14 neoverse_v1 -mcpu=neoverse-v1+sm4+crc+aes+sha3+nopauth"
  "2025.06 GCCcore/14.3.0 gcc-14 a64fx -mcpu=a64fx+crc+sha2"
  "2025.06 GCCcore/14.3.0 gcc-14 neoverse_n1 $(grep -- '-mcpu=' "$A/refs311/neoverse_n1/gcc-14.3.0.txt")"
  "2026.06 GCCcore/15.2.0 gcc-15 grace -mcpu=neoverse-v2+crc+sve2-aes+sve2-sha3+sve2-sm4+norng+nossbs+nopauth"
  "2026.06 GCCcore/15.2.0 gcc-15 graviton4 -mcpu=neoverse-v2+crc+sve2-aes+sve2-sha3+nossbs+nopauth"
  "2026.06 GCCcore/15.2.0 gcc-15 graviton4-ref311 $(grep -- '-mcpu=' "$A/refs311/aws/graviton4/gcc-15.2.0.txt")"
  "2026.06 GCCcore/15.2.0 gcc-15 neoverse_v1 $(grep -- '-mcpu=' "$A/refs311/neoverse_v1/gcc-15.2.0.txt")"
)
for branch in gcc-14 gcc-15; do
  mkdir -p "$W/$branch"
  for f in aarch64-option-extensions.def aarch64-arches.def aarch64-cores.def; do
    curl -sSfL -o "$W/$branch/$f" "https://raw.githubusercontent.com/gcc-mirror/gcc/releases/$branch/gcc/config/aarch64/$f"
  done
done
ok=0; bad=0
for c in "${checks[@]}"; do
  read -r ver mod branch target want <<<"$c"
  view="$W/$target-$branch.cpuinfo"
  python3 "$A/gen_armprofile.py" "$W/$branch" "$want" > "$view" || { echo "GENFAIL $target $branch"; bad=$((bad+1)); continue; }
  got=$(set +u; export EESSI_SOFTWARE_SUBDIR_OVERRIDE=aarch64/neoverse_n1
        source /cvmfs/software.eessi.io/versions/$ver/init/bash >/dev/null 2>&1
        module load "$mod" >/dev/null 2>&1
        GCC_CPUINFO="$view" gcc -mcpu=native -### -E - < /dev/null 2>&1 | awk '$1 ~ /\/cc1$/' | tr -d '"' | tr -s ' ' '\n' | grep -- '^-mcpu=')
  if [ "$got" = "$want" ]; then ok=$((ok+1)); echo "MATCH  $target $mod: $got"
  else bad=$((bad+1)); echo "DIFFER $target $mod: want $want got ${got:-nothing}"; grep Features "$view"; fi
done
echo "generated views: $ok match, $bad differ"
