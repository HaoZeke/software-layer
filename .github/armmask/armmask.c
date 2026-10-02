/*
 * armmask: present an older aarch64 CPU's capabilities to the dynamically
 * linked processes of a tree, without a VM.
 *
 * aarch64 software learns the CPU three ways: getauxval(AT_HWCAP/AT_HWCAP2)
 * (Highway, most runtime dispatchers), /proc/cpuinfo (GCC -mcpu=native,
 * archspec, EESSI archdetect, OpenBLAS getarch), and MRS reads of ID
 * registers, which the kernel emulates without a signal. This library covers
 * the first by interposing getauxval; armmask-run.sh covers the second with a
 * bind-mounted cpuinfo. The third cannot be reached from userspace.
 *
 * Profile from ARMMASK_PROFILE: neoverse_n1 or generic.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>

/* Linux arch/arm64/include/uapi/asm/hwcap.h bit numbers. */
#define B(n) (1UL << (n))
/* Neoverse N1 (Graviton2): fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics
 * fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp ssbs; no HWCAP2 bits. */
static const unsigned long N1_HWCAP = B(0) | B(1) | B(2) | B(3) | B(4) | B(5) | B(6) | B(7) | B(8) |
                                      B(9) | B(10) | B(11) | B(12) | B(15) | B(16) | B(20) | B(28);
/* armv8-a baseline: fp asimd evtstrm cpuid. */
static const unsigned long GENERIC_HWCAP = B(0) | B(1) | B(2) | B(11);

typedef unsigned long (*getauxval_fn)(unsigned long);

unsigned long getauxval(unsigned long type)
{
    static getauxval_fn real;
    if (!real)
        real = (getauxval_fn)dlsym(RTLD_NEXT, "getauxval");
    unsigned long v = real(type);
    const char *p = getenv("ARMMASK_PROFILE");
    if (!p || (type != AT_HWCAP && type != AT_HWCAP2))
        return v;
    unsigned long keep1, keep2 = 0;
    if (strcmp(p, "neoverse_n1") == 0)
        keep1 = N1_HWCAP;
    else if (strcmp(p, "generic") == 0)
        keep1 = GENERIC_HWCAP;
    else
        return v;
    return type == AT_HWCAP ? (v & keep1) : (v & keep2);
}
