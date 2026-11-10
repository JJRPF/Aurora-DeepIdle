#!/usr/bin/env python3
"""Remove every trace of the DeepTest entry from a limine.conf: the marker comments, each /DeepTest
entry with its indented lines, and orphaned DeepTest lines (comment, protocol, path) left without a
header. Usage: limine-strip.py <limine.conf>"""
import sys
p = sys.argv[1]
L = open(p).read().split('\n')
out = []; i = 0
while i < len(L):
    l = L[i]
    if l.startswith('# --- DeepTest '):
        i += 1; continue
    if l.strip() == '/DeepTest':
        i += 1
        while i < len(L) and L[i].startswith(' '):
            i += 1
        continue
    if l.strip() == 'comment: GH-5 USB test root, RAM overlay':
        # orphan block: this comment, then indented lines up to and including the deeptest.efi path
        j = i + 1
        while j < len(L) and L[j].startswith(' ') and 'deeptest.efi' not in L[j]:
            j += 1
        if j < len(L) and 'deeptest.efi' in L[j]:
            i = j + 1; continue
    out.append(l); i += 1
while out and out[-1] == '':
    out.pop()
open(p, 'w').write('\n'.join(out) + '\n')
