#!/usr/bin/env bash
# Boot an Ubuntu arm64 kernel with the given page size (generic = 4K,
# generic-64k = 64K) in qemu-system-aarch64, with this runner's root (and the
# EESSI CernVM-FS mount under it) shared read-only over 9p, and run PAYLOAD
# inside it under chroot. Uses KVM when /dev/kvm is usable, TCG otherwise.
#   pagesize-vm.sh FLAVOUR PAYLOAD OUTFILE
set -euo pipefail
flavour=$1 payload=$(readlink -f "$2") outfile=$(readlink -f "$3")
w=$(mktemp -d)
cd "$w"
img=$(apt-cache depends "linux-image-$flavour" | awk '/Depends: linux-image-[0-9]/ {print $2; exit}')
kver=${img#linux-image-}
kver=${kver#unsigned-}
apt-get download "$img" "linux-modules-$kver" > /dev/null
for d in ./*.deb; do dpkg-deb -x "$d" k; done
kernel=$(ls k/boot/vmlinuz-*)
mods=k/lib/modules/$kver
# 9p over virtio, with every dependency, in load order
want="9pnet_virtio 9p"
order=""
add() {
  local m=$1 f deps
  case " $order " in *" $m "*) return ;; esac
  f=$(find "$mods" -name "$m.ko*" | head -1)
  [ -z "$f" ] && return # built in
  deps=$(modinfo -F depends "$f" | tr ',' ' ')
  for d in $deps; do add "$d"; done
  order="$order $m"
}
for m in $want; do add "$m"; done
mkdir -p ir/bin ir/mods ir/proc ir/sys ir/dev ir/host
cp /usr/bin/busybox ir/bin/busybox
for m in $order; do
  f=$(find "$mods" -name "$m.ko*" | head -1)
  case $f in *.zst) zstd -q -d -c "$f" > "ir/mods/$m.ko" ;; *.xz) xz -d -c "$f" > "ir/mods/$m.ko" ;; *) cp "$f" "ir/mods/$m.ko" ;; esac
done
echo "$order" > ir/modorder
cat > ir/init <<EOF
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev
for m in \$(cat /modorder); do insmod /mods/\$m.ko || echo "insmod \$m failed"; done
mount -t 9p -o trans=virtio,version=9p2000.L,ro,msize=1048576 host /host || echo "9p mount failed"
mount -t proc proc /host/proc; mount -t sysfs sys /host/sys; mount -t devtmpfs dev /host/dev
mount -t tmpfs tmp /host/tmp
echo "GUEST kernel \$(uname -r)"
chroot /host /bin/bash $payload 2>&1
echo "GUEST done"
poweroff -f
EOF
chmod +x ir/init
(cd ir && find . | cpio -o -H newc 2>/dev/null | gzip > ../initrd.gz)
accel="-accel tcg,thread=multi -cpu max,pauth-impdef=on"
if [ -w /dev/kvm ]; then accel="-accel kvm -cpu host"; fi
echo "booting $kver ($accel)"
timeout 3000 qemu-system-aarch64 -M virt $accel -smp 4 -m 4096 -nographic -no-reboot \
  -kernel "$kernel" -initrd initrd.gz -append "console=ttyAMA0 rdinit=/init quiet" \
  -fsdev local,id=h,path=/,security_model=none,readonly=on,multidevs=remap \
  -device virtio-9p-pci,fsdev=h,mount_tag=host > "$outfile" 2>&1 || true
grep -E "GUEST|PAYLOAD|failed" "$outfile" || tail -30 "$outfile"
