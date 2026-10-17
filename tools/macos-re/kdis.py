#!/usr/bin/env python3
"""Annotated disassembly of one kext's __text: kdis.py <entry> > out.s  (KC env = kernelcache)
Annotates adrp+add/ldr string refs, and names functions after the __PRETTY_FUNCTION__ / log
strings they reference first."""
import sys, os, re, subprocess, tempfile
sys.path.insert(0, os.path.dirname(__file__))
import fileset as fs
kc = fs.kc
# string map over all kexts' TEXT sections
strs = {}
ents = list(fs.entries())
for n, vm, fo in ents:
    for seg, sect, addr, size, off in fs.sections(fo):
        if seg == "__TEXT" and sect in ("__cstring", "__os_log"):
            blob = kc[off:off + size]
            for m in re.finditer(rb"[^\0]+", blob):
                strs[addr + m.start()] = m.group()[:160].decode("latin1")
def cstr(a):
    return strs.get(a)
target = sys.argv[1]
fo = next(fo for n, vm, fo in ents if n == target)
text = next(s for s in fs.sections(fo) if s[1] == "__text")
_, _, addr, size, off = text
with tempfile.NamedTemporaryFile(suffix=".bin") as t:
    t.write(kc[off:off + size]); t.flush()
    out = subprocess.run(["objdump", "-D", "-b", "binary", "-m", "aarch64", f"--adjust-vma={addr:#x}",
                          "--no-show-raw-insn", t.name], capture_output=True, text=True).stdout
lines = []
regs = {}
for ln in out.splitlines():
    m = re.match(r"\s*([0-9a-f]+):\s+(\S+)\s*(.*)", ln)
    if not m:
        continue
    a, op, args = int(m.group(1), 16), m.group(2), m.group(3)
    note = ""
    if op == "adrp":
        r, v = re.match(r"(x\d+), 0x([0-9a-f]+)", args).groups()
        regs[r] = int(v, 16)
    elif op == "add" and re.match(r"(x\d+), (x\d+), #0x([0-9a-f]+)$", args):
        d, s, imm = re.match(r"(x\d+), (x\d+), #0x([0-9a-f]+)$", args).groups()
        if s in regs:
            v = regs[s] + int(imm, 16); regs[d] = v
            st = cstr(v)
            note = f"  ; {v:#x}" + (f" \"{st}\"" if st else "")
    elif op.startswith("ldr") and re.search(r"\[(x\d+), #0x([0-9a-f]+)\]", args):
        s, imm = re.search(r"\[(x\d+), #0x([0-9a-f]+)\]", args).groups()
        if s in regs:
            note = f"  ; [{regs[s] + int(imm, 16):#x}]"
    if op in ("ret", "retab", "b") or op.startswith("bl"):
        pass
    lines.append((a, op, args, note))
# function starts: pacibsp, or sub sp / stp x29 after a ret/b
starts = set()
prev = None
for a, op, args, note in lines:
    if (op == "bti" and args.startswith("c")) or (op == "pacibsp" and prev != "bti") or \
            (prev in ("ret", "retab", "b", "brk", "udf", "braa", "braaz", "br") and op in ("stp", "sub", "pacibsp")):
        starts.add(a)
    prev = op
starts = sorted(starts)
import bisect
names = {}
symfile = os.path.join(os.path.dirname(fs.__file__), "..", "13.5-22G74", "syms-demangled.txt")
allsyms = {}
if os.path.exists(symfile):
    for l in open(symfile, encoding="latin1"):
        a_, k_, n_ = l.rstrip("\n").split(" ", 2)
        allsyms.setdefault(int(a_, 16), n_)
pf = re.compile(r"^(virtual |static )?[\w:<>\*&, ]*?([\w:~]+)\(")
for a, op, args, note in lines:
    m = re.search(r'"([^"]*)"$', note)
    if m:
        i = bisect.bisect_right(starts, a) - 1
        if i >= 0 and starts[i] not in names:
            s = m.group(1)
            mm = pf.match(s)
            if mm and "::" in mm.group(2):
                names[starts[i]] = mm.group(2)
for k_, v_ in allsyms.items():
    names[k_] = v_
starts = sorted(set(starts) | {k for k in allsyms if lines and lines[0][0] <= k <= lines[-1][0]})
for a, op, args, note in lines:
    if a in starts:
        print(f"\n{a:#x} <{names.get(a, 'fn_%x' % a)}>:")
    if op.startswith("bl") or op == "b":
        m = re.match(r"0x([0-9a-f]+)", args)
        if m and int(m.group(1), 16) in names:
            note += f"  ; {names[int(m.group(1), 16)]}"
    print(f"  {a:x}: {op} {args}{note}")
