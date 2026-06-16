# Intel IPU4 Kernel Driver

Project state at a glance: <https://kleist.github.io/ipu4-driver/> — code coverage, MMIO divergence, register coverage, milestones, and latest CI status, refreshed on every push to `main` and after each `vm-smoke` run.

This repository contains an out of tree Linux kernel driver for IPU4. It is based on the upstream IPU6 driver which was upstreamed in 6.10. To make future synchronization and upstreaming possible, the code is kept as close as possible to the latest synchronized upstream IPU6 driver.

It is the intention over time to follow upstream kernel development, and submit this driver upstream as well, but there is no timeline for when this will happen.

## Caveats
The driver currently does not work with any publicly available hardware. As a bare minimum, you need to change `ambu_ipu_bridge_*` calls to something else.

## How the IPU4 support is implemented
Whenever there is a diffference between IPU4 and IPU6, it is either handled with `#ifdef IPU6` or with new functions that are named ipu4 instead of ipu6. The `IPU6` define It is not intended to be ever set, it is only there to minimize conflicts when backporting upstream changes. If you need a driver for IPU6, use the one in the kernel.

## Supported Devices
| IPU Version | PCI Device ID | Description |
|-------------|---------------|-------------|
| IPU4        | 0x5a88        | 4th Generation IPU |
| IPU4P       | 0x8a19        | Ice Lake IPU4P, e.g. Surface Pro 7 |

IPU4P support is currently an initial probe path only. The driver binds the
PCI device, requests `ipu4p_cpd.bin`, and labels the media device as `ipu4p`.
On Surface Pro 7 the ACPI camera shape is:

| ACPI node | HID | Sensor | I2C bus/address | Companion |
|-----------|-----|--------|-----------------|-----------|
| `CAMF` | `INT33BE` | OV5693 front camera | `I2C2`, `0x36` | `ICL1` / `INT3472:01` |
| `CAMR` | `INT347A` | OV8865 rear camera | `I2C3`, `0x10` plus VCM at `0x0c` | `ICL0` / `INT3472:00` |
| `CAM3` | `INT347E` | OV7251 IR/depth camera | `I2C3`, `0x60` | `ICL2` / `INT3472:02` |

Those sensor HIDs are already supported by Linux's generic `ipu-bridge.c`, and
without an IPU bridge provider the sensor drivers defer with `waiting for fwnode
graph endpoint`. IPU4P therefore uses upstream `ipu_bridge_init()` with
`ipu_bridge_parse_ssdb()` instead of the Ambu-specific bridge. Full Surface
camera graph/capture still needs hardware validation and follow-up work.

## Tested kernel versions
* 6.18.29

## History
This driver has it's origin in two different drivers:
* The IPU6 driver which was upstreamed by Intel, see https://lore.kernel.org/all/?q=s:%22media:+ipu6:%22 and https://github.com/torvalds/linux/tree/master/drivers/media/pci/intel/ipu6 .
* The IPU4 driver which was part of clear linux https://github.com/clearlinux-pkgs/linux-iot-lts2018

IPU4 support was hacked onto the IPU6 driver to work with 6.6 by @Kleist. See https://lore.kernel.org/all/e136389011517dbc65b30f6bf0b1a9c49ab4e599.camel@gmail.com/ for more information about this work. This work was shared in https://github.com/Kleist/linux/tree/kleist-v6.6-ipu4-hacks-1 .

This branch targets Linux 6.18 LTS / 6.18+ and 7.x only.

## Development & test harness

A QEMU-based dev/test harness lives under `tools/`. It clones Linux at `v6.18.29` and QEMU at `v9.1.0`, seeds the driver into an in-tree path, and provides KUnit + full-VM smoke tests that run entirely in software.

* [CLAUDE.md](CLAUDE.md) — the entry point: prerequisite apt packages, build/test commands, the upstream-IPU6 discipline, and the QEMU device-model workflow. Read this first when picking up the repo.
* [STATUS.md](STATUS.md) — milestone state, layout, and the canonical "Running the harness" recipe.

Quickstart on a fresh Ubuntu 24.04 / Debian box:

```bash
sudo apt-get install -y \
  build-essential bc bison flex libelf-dev libssl-dev kmod \
  python3 python3-pip lcov qemu-system-x86 \
  ninja-build pkg-config libglib2.0-dev libpixman-1-dev \
  meson python3-venv busybox-static cpio gzip
tools/bootstrap.sh
tools/build.sh && tools/tests/kunit.sh
tools/build-qemu.sh && tools/build-kernel.sh && tools/rootfs/build.sh
IPU4_ACCEL=tcg tools/tests/streamon-smoke.sh    # full v4l2 capture-API walk
```

## Upstream sync tooling
* [tools/upstream/diff.sh](tools/upstream/diff.sh): regenerate `tools/notes/upstream-diff/summary.md`, a file-by-file divergence report against upstream `drivers/media/pci/intel/ipu6/` at the pinned tag — input for incrementally retiring `#ifdef IPU6` hunks.
* [tools/upstream/watch.sh](tools/upstream/watch.sh): runs daily in CI (`.github/workflows/upstream-watch.yml`) — detects new upstream IPU6 commits on `linux-6.18.y` and `master`, tries cherry-picks, opens a triage PR.

## Scripts
The scripts added will not work out of the box, but should be seen as a source of inspiration for how one could work with porting this to other devices, or e.g. add IPU4P support.

For the scripts to work, the kernel should be configured with kernel/configs/mmiotrace.config (from the kernel tree)

* [trace_ipu4.sh](trace_ipu4.sh): Setup a stream with media-ctl and capture some frames using gstreamer or yavta
* [trace_functions.sh](trace_functions.sh): Helper functions for trace_ipu4.sh
* [split_trace.sh](split_trace.sh): Split a trace based on the markers inserted by trace_ipu4.sh
* [postprocess_trace.py](postprocess_trace.py): Convert register addresses to register names

## Module Structure

- **intel-ipu4**: Core driver module handling device discovery, initialization, and hardware management
- **intel-ipu4-isys**: Input System module for camera interface and V4L2 video device support
- **ambu-ipu-bridge**: Loads a proprietary driver for a tc358748 Toshiba MIPI Bridge driver.

## License

This project is licensed under the GNU General Public License v2.0 (GPL-2.0-only). See the [LICENSE](LICENSE) file for details.
