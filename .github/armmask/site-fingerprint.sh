#!/usr/bin/env bash
# Print, as one JSON object, the properties of this node that change how the
# same EESSI binary behaves: kernel, page size, CPU identity and the features
# the kernel exposes, SVE vector length, NUMA layout (CPU-less nodes are GPU or
# other device memory), what EESSI's archdetect selects, and the CVMFS client.
# Meant to sit next to every native test-suite result, so a failure on one
# site's Grace and not another's can be told apart by node, not by CPU target.
set -uo pipefail
first() { grep -m1 -i "^$1" /proc/cpuinfo 2>/dev/null | sed 's/^[^:]*:\s*//'; }
arch=$(uname -m)
features=$(first flags); [ -z "$features" ] && features=$(first features)
has() { case " $features " in *" $1 "*) echo true ;; *) echo false ;; esac; }
sve_vl=null
[ -r /proc/sys/abi/sve_default_vector_length ] && sve_vl=$(cat /proc/sys/abi/sve_default_vector_length)
nodes=""
for n in /sys/devices/system/node/node[0-9]*; do
  [ -d "$n" ] || continue
  cpus=$(cat "$n/cpulist" 2>/dev/null)
  mem=$(awk '/MemTotal/ {print $4}' "$n/meminfo" 2>/dev/null)
  nodes="$nodes{\"node\":${n##*node},\"cpus\":\"${cpus}\",\"mem_kib\":${mem:-0}},"
done
cpuless=$(for n in /sys/devices/system/node/node[0-9]*; do [ -z "$(cat "$n/cpulist" 2>/dev/null)" ] && echo "${n##*node}"; done | paste -sd, -)
archdetect=null
if [ -r /cvmfs/software.eessi.io/versions/2025.06/init/eessi_archdetect.sh ]; then
  archdetect="\"$(bash /cvmfs/software.eessi.io/versions/2025.06/init/eessi_archdetect.sh cpupath 2>/dev/null)\""
fi
cvmfs=$(cvmfs2 --version 2>/dev/null | head -1 | sed 's/.*version //')
cat <<EOF
{
  "kernel": "$(uname -r)",
  "page_size": $(getconf PAGESIZE),
  "arch": "$arch",
  "vendor": "$(first vendor_id)",
  "model_name": "$(first 'model name')",
  "cpu_family": "$(first 'cpu family')",
  "model": "$(first 'model\s*:' )",
  "cpu_implementer": "$(first 'CPU implementer')",
  "cpu_part": "$(first 'CPU part')",
  "features": "$features",
  "kernel_hides": {"ssbs_visible": $(has ssbs), "paca_visible": $(has paca), "bti_visible": $(has bti), "shstk_visible": $(has user_shstk)},
  "sve_default_vector_length_bytes": $sve_vl,
  "numa_nodes": [${nodes%,}],
  "cpuless_numa_nodes": "${cpuless}",
  "thp": "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)",
  "archdetect_2025_06": $archdetect,
  "cvmfs_client": "${cvmfs}"
}
EOF
