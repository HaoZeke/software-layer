"""Generate the /proc/cpuinfo view of an aarch64 CPU target from its -mcpu string.

GCC's aarch64 driver turns -mcpu=native into a core name and extensions by
reading /proc/cpuinfo: the CPU part picks the core, then every extension whose
cpuinfo strings are all present is kept and the others are dropped. This
inverts that with GCC's own tables, so the view comes from the recorded target
string, not from a dump of some machine:

  aarch64-cores.def             core -> architecture, default extensions, part
  aarch64-arches.def            architecture -> what it implies
  aarch64-option-extensions.def extension -> requires, explicit on/off, cpuinfo strings

    python gen_armprofile.py GCC_DEF_DIR "-mcpu=CORE+ext+noext..." > cpuinfo

The test of the result is GCC_CPUINFO=cpuinfo gcc -mcpu=native -### giving the
same -mcpu string back.
"""
import os
import re
import sys


def items(text, macro):
    return re.finditer(macro, text, re.S)


def split(lst):
    return [x.strip() for x in lst.split(",") if x.strip()]


def load(d):
    ext = {}
    t = open(os.path.join(d, "aarch64-option-extensions.def")).read()
    for m in items(t, r'AARCH64_OPT(?:_FMV)?_EXTENSION\s*\(\s*"([^"]+)"\s*,\s*(\w+)\s*,\s*\(([^)]*)\)\s*,\s*\(([^)]*)\)\s*,\s*\(([^)]*)\)\s*,\s*"([^"]*)"'):
        name, ident, req, on, off, feat = m.groups()
        ext[ident] = dict(name=name, req=split(req), on=split(on), off=split(off), feat=feat.split())
    arch = {}
    t = open(os.path.join(d, "aarch64-arches.def")).read()
    for m in items(t, r'AARCH64_ARCH\s*\(\s*"[^"]+"\s*,\s*\w+\s*,\s*(\w+)\s*,\s*\d+\s*,\s*\(([^)]*)\)'):
        arch[m.group(1)] = split(m.group(2))
    core = {}
    t = open(os.path.join(d, "aarch64-cores.def")).read()
    for m in items(t, r'AARCH64_CORE\s*\(\s*"([^"]+)"\s*,\s*\w+\s*,\s*\w+\s*,\s*(\w+)\s*,\s*\(([^)]*)\)\s*,\s*\w+\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)'):
        core.setdefault(m.group(1), dict(arch=m.group(2), flags=split(m.group(3)), imp=m.group(4), part=m.group(5)))
    return ext, arch, core


def closure(idents, ext, arch):
    out, todo = set(), list(idents)
    while todo:
        x = todo.pop()
        if x in out:
            continue
        out.add(x)
        todo += arch.get(x, []) + ext.get(x, {}).get("req", [])
    return out


def dependents(ident, ext, arch):
    """Every extension whose requirement closure includes ident."""
    return {e for e in ext if ident in closure([e], ext, arch)}


def main(argv):
    d, mcpu = argv[0], argv[1]
    ext, arch, core = load(d)
    by_name = {v["name"]: k for k, v in ext.items()}
    parts = mcpu.removeprefix("-mcpu=").split("+")
    c = core[parts[0]]
    on = closure([c["arch"]] + c["flags"], ext, arch)
    for p in parts[1:]:
        if p.startswith("no") and p[2:] in by_name:
            ident = by_name[p[2:]]
            drop = dependents(ident, ext, arch)
            for o in ext[ident]["off"]:
                drop |= dependents(o, ext, arch)
            on -= drop
        else:
            ident = by_name[p]
            on |= closure([ident] + ext[ident]["on"], ext, arch)
    feats = []
    for ident in ext:  # table order, as the kernel roughly prints them
        if ident in on:
            for f in ext[ident]["feat"]:
                if f not in feats:
                    feats.append(f)
    for f in ("evtstrm", "cpuid"):
        if f not in feats:
            feats.append(f)
    print("processor\t: 0")
    print("BogoMIPS\t: 2000.00")
    print("Features\t: " + " ".join(feats))
    print(f"CPU implementer\t: {c['imp']}")
    print("CPU architecture: 8")
    print("CPU variant\t: 0x0")
    print(f"CPU part\t: {c['part']}")
    print("CPU revision\t: 0")
    print()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
