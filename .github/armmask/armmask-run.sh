#!/usr/bin/env bash
# Run a command with an older aarch64 CPU's view: getauxval masked by
# libarmmask.so and a /proc/cpuinfo whose Features (and, for neoverse_n1, CPU
# part) match the profile. Uses sudo for the bind mount (CI runner).
#   ARMMASK_PROFILE=neoverse_n1|generic armmask-run.sh CMD [ARGS...]
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
profile=${ARMMASK_PROFILE:?}
fake=$(mktemp)
case $profile in
  neoverse_n1) feats="fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp ssbs"
               sed -E -e "s/^(Features\s*:).*/\1 $feats/" -e 's/^(CPU part\s*:).*/\1 0xd0c/' /proc/cpuinfo > "$fake" ;;
  generic)     feats="fp asimd evtstrm cpuid"
               sed -E -e "s/^(Features\s*:).*/\1 $feats/" /proc/cpuinfo > "$fake" ;;
  *) echo "armmask-run: unknown profile $profile" >&2; exit 2 ;;
esac
sudo mount --bind "$fake" /proc/cpuinfo
trap 'sudo umount /proc/cpuinfo; rm -f "$fake"' EXIT
export ARMMASK_PROFILE=$profile
LD_PRELOAD="$here/libarmmask.so${LD_PRELOAD:+:$LD_PRELOAD}" "$@"
