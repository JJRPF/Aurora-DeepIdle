#!/usr/bin/env python3
"""Bisect the PMGR AP wake sources that Aura's deep WFI needs (worklog 2026-11-06, runs L and M).

With macOS's wake mask (deep_steps bit 16) nothing wakes the boot CPU, not even with the SoC up
(worklog 2026-11-05 08:00). Each run keeps macOS's 22 sources plus a test set enabled
(macsmc_reboot.wake_extra) on the normal path (no slpa) and reports whether the alarm woke it.

  wake-bisect.py init          start: every valid bit macOS disables is a candidate
  wake-bisect.py next          print the wake_extra words for the next run (the first half)
  wake-bisect.py result wake|nowake
  wake-bisect.py show

A wake keeps the tested half, no wake keeps the other half. That assumes the needed sources lie in
one half; the last bit is checked alone before it counts as found.
"""
import json, os, sys

STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'wake-bisect', 'state.json')
VALID_BITS = 9 * 32 - 25  # bits 0..262 (word 8 is 0x7f)
MACOS = [0x0c005000, 0x005e0900, 0x04200000, 0xc0000000, 0x0000003f, 0, 0x80000000, 0, 0]
macos_bits = {w * 32 + b for w, v in enumerate(MACOS) for b in range(32) if v >> b & 1}


def words(bits):
    w = [0] * 9
    for b in bits:
        w[b // 32] |= 1 << (b % 32)
    return ','.join('0x%08x' % x for x in w)


def load():
    with open(STATE) as f:
        return json.load(f)


def save(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, 'w') as f:
        json.dump(s, f, indent=1)
        f.write('\n')


def half(c):
    return c[:len(c) // 2] if len(c) > 1 else c


cmd = sys.argv[1] if len(sys.argv) > 1 else 'show'
if cmd == 'init':
    cand = [b for b in range(VALID_BITS) if b not in macos_bits]
    save({'candidates': cand, 'testing': None, 'history': []})
    print(len(cand), 'candidates')
elif cmd == 'next':
    s = load()
    t = half(s['candidates'])
    s['testing'] = t
    save(s)
    print(words(t))
elif cmd == 'result':
    r = sys.argv[2]
    assert r in ('wake', 'nowake')
    s = load()
    t, c = s['testing'], s['candidates']
    assert t is not None, 'no run armed'
    s['history'].append({'tested': t, 'result': r, 'candidates_before': len(c)})
    if r == 'wake':
        s['candidates'] = t
    elif len(c) > 1:
        s['candidates'] = [b for b in c if b not in t]
    else:
        s['candidates'] = []  # the last bit alone did not wake: more than one source is needed
    s['testing'] = None
    save(s)
    print('candidates left:', len(s['candidates']), s['candidates'][:16])
else:
    s = load()
    print('candidates:', len(s['candidates']), s['candidates'][:32])
    print('testing:', s['testing'] and len(s['testing']))
    for h in s['history']:
        print(h['result'], len(h['tested']), 'of', h['candidates_before'], h['tested'][:8])
