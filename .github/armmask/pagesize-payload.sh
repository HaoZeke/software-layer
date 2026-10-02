#!/bin/bash
# Runs inside the pagesize VM: page size, then EESSI 2023.06 Ruby builds
# (the support#197 case) and a few other compat-layer programs.
echo "PAYLOAD pagesize $(getconf PAGESIZE)"
R=/cvmfs/software.eessi.io/versions/2023.06
for t in nvidia/grace neoverse_v1 neoverse_n1; do
  for v in 3.2.2-GCCcore-12.2.0 3.3.0-GCCcore-12.3.0 3.4.2-GCCcore-13.2.0; do
    d=$R/software/linux/aarch64/$t/software/Ruby/$v
    [ -x "$d/bin/ruby" ] || { echo "PAYLOAD ruby $t $v absent"; continue; }
    out=$(LD_LIBRARY_PATH=$d/lib timeout 300 "$d/bin/ruby" --version 2>&1); rc=$?
    echo "PAYLOAD ruby --version $t $v rc=$rc ${out:0:60}"
    out=$(LD_LIBRARY_PATH=$d/lib timeout 300 "$d/bin/ruby" -e 'Fiber.new{}.resume; puts "fiber ok"' 2>&1 | tail -1); rc=$?
    echo "PAYLOAD ruby fiber $t $v rc=$rc ${out:0:60}"
  done
done
for b in $R/compat/linux/aarch64/usr/bin/python3 $R/compat/linux/aarch64/usr/bin/perl; do
  out=$(timeout 120 "$b" --version 2>&1 | head -2 | tr '\n' ' '); echo "PAYLOAD $(basename $b) rc=$? ${out:0:60}"
done
