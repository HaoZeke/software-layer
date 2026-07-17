#!/usr/bin/env bash
# Lab fork wrapper: skip full CUDA host_injections install so CPU smoke
# (cowsay) is not blocked by multi-GB CUDA SDK installs on GPU hosts.
set -e

git clone https://github.com/EESSI/software-layer-scripts

for file in $(ls software-layer-scripts | egrep -v "easystacks|LICENSE|README.md|^bot"); do
    ln -s software-layer-scripts/${file}
done

for file in $(ls software-layer-scripts/bot | grep -v "^build.sh"); do
    ln -s ../software-layer-scripts/bot/${file} bot/${file}
done

# CI-style: do not install full CUDA SDKs under host_injections
software-layer-scripts/bot/build.sh --skip-cuda-install "$@"
