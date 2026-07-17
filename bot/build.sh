#!/usr/bin/env bash
# Lab fork wrapper: skip full CUDA host_injections so CPU smoke can finish.
set -euo pipefail

git clone https://github.com/EESSI/software-layer-scripts

for file in $(ls software-layer-scripts | egrep -v "easystacks|LICENSE|README.md|^bot"); do
    ln -sfn "software-layer-scripts/${file}" "${file}"
done

# Do not overwrite lab bot/build.sh or bot/test.sh wrappers
for file in $(ls software-layer-scripts/bot | grep -vE "^(build|test)\\.sh$"); do
    ln -sfn "../software-layer-scripts/bot/${file}" "bot/${file}"
done

software-layer-scripts/bot/build.sh --skip-cuda-install "$@"
