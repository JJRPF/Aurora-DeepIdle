#!/usr/bin/env python3
"""Rewrite docs/s2r-status.json in its house style: phases expanded,
other arrays of objects one object per line. Usage: s2r-status-fmt.py [path]"""
import json, sys

def one(v):
    if isinstance(v, dict):
        return '{ ' + ', '.join(f'{json.dumps(k)}: {json.dumps(x, ensure_ascii=False)}' for k, x in v.items()) + ' }'
    return json.dumps(v, ensure_ascii=False)

def fmt(d):
    out = ['{']
    keys = list(d)
    for i, k in enumerate(keys):
        v = d[k]
        comma = ',' if i < len(keys) - 1 else ''
        if k == 'phases':
            body = json.dumps(v, ensure_ascii=False, indent=2).replace('\n', '\n  ')
            out.append(f'  "{k}": {body}{comma}')
        elif isinstance(v, list) and v:
            out.append(f'  "{k}": [')
            out += [f'    {one(x)}' + (',' if j < len(v) - 1 else '') for j, x in enumerate(v)]
            out.append(f'  ]{comma}')
        elif isinstance(v, dict):
            body = json.dumps(v, ensure_ascii=False, indent=2).replace('\n', '\n  ')
            out.append(f'  "{k}": {body}{comma}')
        else:
            out.append(f'  "{k}": {json.dumps(v, ensure_ascii=False)}{comma}')
    out.append('}')
    return '\n'.join(out) + '\n'

p = sys.argv[1] if len(sys.argv) > 1 else 'docs/s2r-status.json'
d = json.load(open(p))
s = fmt(d)
assert json.loads(s) == d
open(p, 'w').write(s)
