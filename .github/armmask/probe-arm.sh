#!/bin/bash
# What each detector believes this aarch64 CPU is.
set +u
echo "== cpuinfo"; grep -m1 -E "^CPU implementer" /proc/cpuinfo; grep -m1 -E "^CPU part" /proc/cpuinfo; grep -m1 -E "^Features" /proc/cpuinfo
source /cvmfs/software.eessi.io/versions/2025.06/init/bash >/dev/null 2>&1
echo "EESSI_SOFTWARE_SUBDIR=$EESSI_SOFTWARE_SUBDIR"
echo "archdetect=$($EESSI_PREFIX/init/eessi_archdetect.sh cpupath 2>&1)"
module load GCC/14.3.0 >/dev/null 2>&1
echo 'int main(void){return 0;}' > /tmp/x.c
echo "gcc -mcpu=native -> $(gcc -mcpu=native -### -c /tmp/x.c 2>&1 | grep -o -E -- '-mcpu=[^ "]+' | head -1)"
module purge >/dev/null 2>&1; module load EasyBuild >/dev/null 2>&1
python3 -c 'import archspec.cpu as c; print("archspec host:", c.host().name)' 2>&1
[ -x "$HWY_LIST" ] && "$HWY_LIST" 2>&1 | grep -E "CPU supports|HWY_STATIC_TARGET" | sed 's/^/HWY: /'
