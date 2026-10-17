#!/usr/bin/env python3
"""tools-inline.py <file.c> <kext>...: replace UNK_<addr> refs with string literals"""
import re, sys
strs = {}
for k in sys.argv[2:]:
    for l in open(f"/home/jjr/Work/macos-re/13.5-22G74/strings/{k}.txt"):
        a, s, v = l.split(" ", 2); strs[int(a, 16)] = eval(v)
t = open(sys.argv[1]).read()
t = re.sub(r"&?(?:UNK|DAT|s)_([0-9a-f]{16})", lambda m: (lambda v: repr(strs[v][:100]) if v in strs else m.group(0))(int(m.group(1), 16)), t)
open(sys.argv[1], "w").write(t)
