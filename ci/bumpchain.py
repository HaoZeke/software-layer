"""Bump a set of names to the 2026.1 generation in dependency order.

For each name, take the newest non-CUDA recipe at 2025b (else 2025a) and run
`eb-stack package bump`. When the profile solve reports an unresolved
dependency, bump that dependency first, add its output to the robot path,
and retry. Every bump that resolves stays on the path for the ones after it.
Usage: bumpchain.py <eb-stack binary> <baseline out dir> <out dir> NAME...
"""
import os, re, subprocess, sys
binary, base, out, *names = sys.argv[1:]
tree = os.path.join(base, [d for d in os.listdir(base) if d.startswith('develop-')][0], 'easybuild/easyconfigs')
robot = [tree, os.path.join(base, 'overlay')]
os.makedirs(out, exist_ok=True)
TC = {'foss': '2026.1', 'gompi': '2026.1', 'gfbf': '2026.1', 'GCC': '15.2.0', 'GCCcore': '15.2.0'}
spell = {n.lower(): (l, n) for l in os.listdir(tree) for n in os.listdir(os.path.join(tree, l))}
def source(name):
    l, n = spell.get(name.lower(), (None, None))
    if not l: return None
    files = sorted(os.listdir(os.path.join(tree, l, n)))
    for gen in (r'(2025b|14\.3\.0)', r'(2025a|14\.2\.0)'):
        hits = [f for f in files if f.endswith('.eb') and 'CUDA' not in f
                and re.search(r'-(foss|gompi|gfbf|GCC|GCCcore)-' + gen + r'(\.eb|-)', f)]
        if hits:
            hits.sort(key=lambda f: [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', f)])
            return os.path.join(tree, l, n, hits[-1])
    return None
done, failed, order = {}, {}, []
def bump(name, depth=0):
    if name in done or name in failed: return name in done
    if depth > 8: failed[name] = 'chain too deep'; return False
    src = source(name)
    if not src: failed[name] = 'no 2025a/b recipe'; return False
    tcn = re.search(r"toolchain\s*=\s*\{'name':\s*'([^']+)'", open(src).read()).group(1)
    if tcn not in TC: failed[name] = f'toolchain {tcn}'; return False
    tried = set()
    while True:
        dst = os.path.join(out, name)
        subprocess.run(['rm', '-rf', dst])
        args = [binary, 'package', 'bump', '--source', src, '--toolchain-name', tcn,
                '--toolchain-version', TC[tcn], '--out-dir', dst] + sum([['--easyconfigs', r] for r in robot], [])
        r = subprocess.run(args, capture_output=True, text=True)
        open(dst + '.log', 'w').write(r.stdout + r.stderr)
        if r.returncode == 0:
            done[name] = os.path.basename(src); order.append(name)
            robot.append(os.path.join(dst, 'easyconfigs'))
            return True
        m = re.search(r'unresolved dependency (\S+) ', r.stdout + r.stderr)
        if not m or m.group(1) in tried:
            failed[name] = (r.stdout + r.stderr).strip().splitlines()[-1][:160] if not m else f'needs {m.group(1)}'
            return False
        dep = m.group(1); tried.add(dep)
        if not bump(dep, depth + 1):
            failed[name] = f'needs {dep} ({failed.get(dep)})'; return False
for n in names: bump(n)
print('bump order:', ' '.join(order))
for n, why in failed.items(): print(f'not bumped: {n}: {why}')
open(os.path.join(out, 'order.txt'), 'w').write('\n'.join(order) + '\n')
