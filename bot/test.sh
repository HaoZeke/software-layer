#!/usr/bin/env bash
# Lab wrapper: do not attach --nvidia for CPU-only builds (host may have GPUs;
# --nv + --contain can break /dev/fuse and CVMFS inside the test container).
set -euo pipefail

# Ensure software-layer-scripts is present (build step usually already cloned it)
if [[ ! -d software-layer-scripts ]]; then
  git clone https://github.com/EESSI/software-layer-scripts
fi
# Symlinks if missing (same as build.sh)
if [[ ! -e scripts/utils.sh ]]; then
  for file in $(ls software-layer-scripts | egrep -v "easystacks|LICENSE|README.md|^bot"); do
    ln -sfn software-layer-scripts/${file} ${file}
  done
fi
if [[ ! -e bot/check-test.sh ]]; then
  for file in $(ls software-layer-scripts/bot | grep -v "^test.sh"); do
    ln -sfn ../software-layer-scripts/bot/${file} bot/${file}
  done
fi

# Hide nvidia-smi for this process tree so bot/test.sh nvidia_gpu_available returns false
# when job architecture has no accelerator (CPU smoke).
JOB_CFG="${JOB_CFG_FILE_OVERRIDE:-./cfg/job.cfg}"
ACCEL=""
if [[ -r "$JOB_CFG" ]]; then
  ACCEL=$(awk "
    /^\\[architecture\\]/ {in_arch=1; next}
    /^\\[/ {in_arch=0}
    in_arch && /^accelerator[ \\t]*=/ {
      sub(/^[^=]*=[ \\t]*/, \"\"); print; exit
    }
  " "$JOB_CFG" | tr -d "[:space:]")
fi
if [[ -z "$ACCEL" || "$ACCEL" == "None" || "$ACCEL" == "none" ]]; then
  echo "lab bot/test.sh: CPU-only job (accelerator empty); hiding nvidia-smi"
  mkdir -p /tmp/lab_bin_hide_$$
  cat > /tmp/lab_bin_hide_$$/nvidia-smi << "NS"
#!/bin/sh
echo "lab: nvidia-smi hidden for CPU-only bot test step" >&2
exit 1
NS
  chmod +x /tmp/lab_bin_hide_$$/nvidia-smi
  export PATH="/tmp/lab_bin_hide_$$:$PATH"
fi

# Prefer home-backed tmp (also set by site_config / job.cfg)
export BOT_SHARED="${BOT_SHARED:-/home/rgoswami/Git/Github/SURF/eessi-bot/shared}"
export PYTHONPATH="${BOT_SHARED}/python_site${PYTHONPATH:+:$PYTHONPATH}"
export EESSI_PROPAGATE_INTO_PREFIX_PYTHONPATH="${BOT_SHARED}/python_site${EESSI_PROPAGATE_INTO_PREFIX_PYTHONPATH:+:$EESSI_PROPAGATE_INTO_PREFIX_PYTHONPATH}"
export RFM_CONFIG_FILES="${BOT_SHARED}/reframe_config.py"
export REFRAME_SCALE_TAG="${REFRAME_SCALE_TAG:---tag 4_cores}"

exec software-layer-scripts/bot/test.sh "$@"
