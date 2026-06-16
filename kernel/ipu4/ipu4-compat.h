#ifndef IPU4_COMPAT_H
#define IPU4_COMPAT_H

#include <linux/version.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0)
#error "ipu4-driver targets Linux 6.18 LTS / 6.18+ and 7.x only"
#endif

/*
 * These namespace constants are string literals on the supported kernel lines.
 * Older compatibility shims were intentionally removed with the 6.18+ baseline.
 */
#define INTEL_IPU_BRIDGE "INTEL_IPU_BRIDGE"
#define INTEL_IPU6 "INTEL_IPU6"

#endif // IPU4_COMPAT_H
