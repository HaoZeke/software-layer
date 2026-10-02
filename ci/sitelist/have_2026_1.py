"""Print the names from a roots file that have a 2026.1-generation recipe in a tree."""
import os, re, sys

tree, roots = sys.argv[1], sys.argv[2]
gen = re.compile(r'-(foss|gompi|gfbf|GCC|GCCcore)-(2026\.1|15\.2\.0)(-|\.eb$)')
have = {}
for d, _, fs in os.walk(tree):
    for f in fs:
        if f.endswith('.eb') and gen.search(f):
            have[os.path.basename(d).lower()] = os.path.basename(d)
want = [l.strip() for l in open(roots) if l.strip()]
for w in want:
    if w in have:
        print(have[w])
print(f'{sum(w in have for w in want)} of {len(want)} names have a 2026.1 recipe', file=sys.stderr)
