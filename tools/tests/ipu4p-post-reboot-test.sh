#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build and temporarily load the IPU4P modules on a Surface Pro 7 after a
# clean boot, then collect the probe state and relevant kernel log lines.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$script_dir/../.." && pwd)
kmod_dir="$repo/kernel/ipu4"
ts=$(date +%Y%m%d-%H%M%S)
log_dir="$repo/logs"
log="$log_dir/ipu4p-post-reboot-test-$ts.log"
build_log="$log_dir/ipu4p-post-reboot-build-$ts.log"
clean_log="$log_dir/ipu4p-post-reboot-clean-$ts.log"
pattern='intel-ipu4|intel_ipu4|ipu4p|ipu bridge|ipu-bridge|ov5693|ov8865|ov7251|dw9719|INT33BE|INT347A|INT347E|INT3472|firmware|cpd|CSE|BOOT_LOAD|AUTHENTICATE|deferred|fwnode|media|buttress|power status|Change power|timeout|isys|psys|auxiliary|DMA|iommu|page fault|fault|IRQ|ipc'

mkdir -p "$log_dir"
exec > >(tee "$log") 2>&1

section() { printf '\n===== %s =====\n' "$1"; }

section "environment"
date -Is
uname -a
cd "$repo" || exit 1
git status --short
git log --oneline -5

section "firmware"
if [ -r /usr/lib/firmware/ipu4p_cpd.bin ]; then
	sha256sum /usr/lib/firmware/ipu4p_cpd.bin
else
	echo "missing /usr/lib/firmware/ipu4p_cpd.bin"
fi

section "pre-load state"
if [ -r /sys/module/intel_ipu4/initstate ]; then
	printf 'intel_ipu4 initstate: '
	cat /sys/module/intel_ipu4/initstate
else
	echo 'intel_ipu4 module not present before test'
fi
lsmod | grep -E '^(intel_ipu4|intel_ipu4_isys|ipu_bridge|ov5693|ov8865|ov7251|intel_skl_int3472|videobuf2|v4l2|videodev|mc)' || true
if [ -e /sys/bus/pci/devices/0000:00:05.0/driver ]; then
	printf 'PCI 0000:00:05.0 driver: '
	readlink -f /sys/bus/pci/devices/0000:00:05.0/driver
else
	echo 'PCI 0000:00:05.0 has no bound driver before test'
fi
for pat in /dev/media* /dev/video* /dev/v4l-subdev*; do
	found=0
	for node in $pat; do
		[ -e "$node" ] || continue
		found=1
		ls -l "$node"
	done
	[ "$found" -eq 1 ] || echo "no nodes for $pat before test"
done

section "build"
cd "$kmod_dir" || exit 1
make clean >"$clean_log" 2>&1 || true
if make KERNEL_SRC="/lib/modules/$(uname -r)/build" >"$build_log" 2>&1; then
	build_rc=0
else
	build_rc=$?
fi
echo "build rc=$build_rc log=$build_log"
grep -nEi 'error:|fatal:|warning:|MODPOST|LD \[M\]|CC \[M\]|undefined' "$build_log" | tail -n 240 || true
if [ "$build_rc" -ne 0 ]; then
	exit "$build_rc"
fi
modinfo ./intel-ipu4.ko | grep -E '^(filename|firmware|alias|depends|name|vermagic|import_ns):' || true
modinfo ./intel-ipu4-isys.ko | grep -E '^(filename|firmware|alias|depends|name|vermagic|import_ns):' || true

section "load dependencies"
for mod in mc videodev videobuf2-common videobuf2-v4l2 videobuf2-dma-sg v4l2-fwnode v4l2-async ipu_bridge; do
	sudo modprobe "$mod"
	echo "modprobe $mod rc=$?"
done

section "load intel-ipu4 core"
sudo timeout 120s insmod ./intel-ipu4.ko
core_rc=$?
echo "intel-ipu4 insmod rc=$core_rc"
if [ -r /sys/module/intel_ipu4/initstate ]; then
	printf 'intel_ipu4 initstate after core load: '
	cat /sys/module/intel_ipu4/initstate
fi
if [ -e /sys/bus/pci/devices/0000:00:05.0/driver ]; then
	printf 'PCI 0000:00:05.0 driver after core load: '
	readlink -f /sys/bus/pci/devices/0000:00:05.0/driver
else
	echo 'PCI 0000:00:05.0 has no bound driver after core load'
fi
find /sys/bus/auxiliary/devices -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort | grep -E 'intel_ipu4|ipu4' || true

section "load intel-ipu4-isys"
if [ "$core_rc" -eq 0 ]; then
	sudo timeout 120s insmod ./intel-ipu4-isys.ko
	isys_rc=$?
else
	echo 'skip isys load because core load did not complete successfully'
	isys_rc=99
fi
echo "intel-ipu4-isys insmod rc=$isys_rc"

section "post-load state"
lsmod | grep -E '^(intel_ipu4|intel_ipu4_isys|ipu_bridge|ov5693|ov8865|ov7251|intel_skl_int3472|videobuf2|v4l2|videodev|mc)' || true
for pat in /dev/media* /dev/video* /dev/v4l-subdev*; do
	found=0
	for node in $pat; do
		[ -e "$node" ] || continue
		found=1
		ls -l "$node"
	done
	[ "$found" -eq 1 ] || echo "no nodes for $pat after test"
done
find /sys/bus/auxiliary/devices -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort | grep -E 'intel_ipu4|ipu4' || true

section "deferred probe"
if [ -r /sys/kernel/debug/devices_deferred ]; then
	sudo cat /sys/kernel/debug/devices_deferred | grep -Ei 'INT33BE|INT347A|INT347E|ov5693|ov8865|ov7251|ipu|camera|cam' || true
else
	echo '/sys/kernel/debug/devices_deferred unavailable'
fi

section "dmesg relevant tail"
sudo dmesg -T | grep -Ei "$pattern" | tail -n 500 || true

section "logs"
echo "main log: $log"
echo "build log: $build_log"
echo "clean log: $clean_log"
exit 0
