#!/usr/bin/env python3
"""Derive opp-microwatt for the T602x (M2 Pro/Max) CPU OPP tables.

  t6020-cpu-em.py [--write]

Without an energy model the scheduler's energy-aware placement (EAS) is
off: on T602x the CPU OPP tables have no opp-microwatt, while T8103, T600x,
T8112 and T8140 have measured ones. T8112 (M2) has the same cores as T602x,
Blizzard and Avalanche, on the same process, so its measurements carry over
once the voltage of each OPP is taken into account.

T8112's per-OPP power (its opp-microwatt, measured with the SMC's cluster
power meter) is fitted to P = (a + b f) V^2 f per core type, where V is
T6020's voltage for that frequency: a switching capacitance that grows
slowly with frequency, which absorbs leakage and temperature at the top.
A T8112 point gets the voltage of the lowest T6020 OPP at or above its
frequency (an upper bound when the two tables differ); points outside
T6020's range are left out, since their voltage is unknown. The fitted
model then gives T6020's OPPs: within 6% rms of T8112's measurements for
both core types.

Its energy per cycle, (a + b f) V^2, rises from each OPP to the next, so
the energy model marks no OPP inefficient and cpufreq keeps choosing among
all of them as it does today; only the scheduler's placement changes.

The voltages are those of a J414s (M2 Pro, 10 cores), from the ADT's
/arm-io/pmgr voltage-states1 (E cluster) and voltage-states5 (P cluster 0;
cluster 1's voltage-states13 is within 6 mV), whose cells are pairs of
(65536000 / MHz, mV). Prints the fit and each table's values; --write
puts them into t602x-common.dtsi as each OPP's opp-microwatt. It reads
the kernel tree it sits in, or the one AURORA_TREE names.
"""
import argparse
import os
from pathlib import Path
import re
import sys

# The kernel tree: this script's own, or AURORA_TREE when run from a copy outside it.
ROOT = Path(os.environ.get('AURORA_TREE') or Path(__file__).resolve().parents[2])
T8112 = ROOT / 'arch/arm64/boot/dts/apple/t8112.dtsi'
T602X = ROOT / 'arch/arm64/boot/dts/apple/t602x-common.dtsi'

# (MHz, mV) for each T6020 OPP, in the order of t602x-common.dtsi.
T6020_E = [(912, 612), (1284, 681), (1752, 775), (2004, 834), (2256, 887), (2424, 946)]
T6020_P = [(702, 600), (948, 625), (1188, 646), (1452, 687), (1704, 718), (1968, 759),
           (2208, 793), (2400, 825), (2568, 856), (2724, 896), (2868, 931), (3000, 975),
           (3132, 1012), (3264, 1056), (3360, 1056), (3408, 1056), (3504, 1056)]
TABLES = {'blizzard_opp': ('ecluster_opp', T6020_E), 'avalanche_opp': ('pcluster_opp', T6020_P)}


def opp_table(source, label):
    """[(MHz, opp-microwatt or None)] of the OPP table with that label."""
    start = source.index(f'{label}: ')
    body = source[start:source.index('\n\t};', start)]
    rows = []
    for node in re.findall(r'opp\d+ \{(.*?)\}', body, re.S):
        hz = re.search(r'opp-hz = /bits/ 64 <(\d+)>', node)
        uw = re.search(r'opp-microwatt = <(\d+)>', node)
        rows.append((int(hz.group(1)) // 1000000, int(uw.group(1)) if uw else None))
    return rows


def points(measured, volts):
    """(MHz, mV, uW) for each measured OPP in T6020's range, at the voltage of the next
    T6020 OPP up."""
    out = []
    for mhz, uw in measured:
        above = [mv for f, mv in volts if f >= mhz]
        if above and mhz >= volts[0][0]:
            out.append((mhz, above[0], uw))
    return out


def fit(data):
    """(a, b) of P = (a + b f) V^2 f, least squares on the relative error."""
    rows = [(v * v * f / p, v * v * f * f / p) for f, v, p in ((f, v / 1000, p) for f, v, p in data)]
    s11 = sum(x * x for x, _ in rows)
    s12 = sum(x * y for x, y in rows)
    s22 = sum(y * y for _, y in rows)
    t1 = sum(x for x, _ in rows)
    t2 = sum(y for _, y in rows)
    det = s11 * s22 - s12 * s12
    return (t1 * s22 - t2 * s12) / det, (s11 * t2 - s12 * t1) / det


def model(coef, mhz, mv):
    a, b = coef
    v = mv / 1000
    return (a + b * mhz) * v * v * mhz


def microwatts(coef, volts):
    """opp-microwatt for each OPP, rounded to the milliwatt."""
    return [(mhz, round(model(coef, mhz, mv) / 1000) * 1000) for mhz, mv in volts]


def inefficient(table, capacity=1024):
    """The OPPs the energy model would mark inefficient, in em_compute_costs()'s integer
    arithmetic: cost = power * 10 / performance, performance = capacity * f / fmax, an OPP
    being inefficient when its cost is not below that of every faster one."""
    fmax = table[-1][0]
    out, prev = [], None
    for mhz, uw in reversed(table):
        cost = uw * 10 // (capacity * mhz // fmax)
        if prev is not None and cost >= prev:
            out.append(mhz)
        else:
            prev = cost
    return sorted(out)


def derive(source):
    """{T6020 label: (coef, rms relative error, [(MHz, uW)])}."""
    out = {}
    for label, (t8112_label, volts) in TABLES.items():
        data = points(opp_table(source, t8112_label), volts)
        coef = fit(data)
        rms = (sum(((model(coef, f, v) - p) / p) ** 2 for f, v, p in data) / len(data)) ** 0.5
        out[label] = coef, rms, microwatts(coef, volts)
    return out


def apply(source, derived):
    """The T602x source with each CPU OPP's opp-microwatt set to the derived value."""
    for label, (_, _, table) in derived.items():
        start = source.index(f'{label}: ')
        end = source.index('\n\t};', start)
        body = source[start:end]
        values = iter(table)

        def node(match):
            text = re.sub(r'\n\t\t\topp-microwatt = <\d+>;', '', match.group(0))
            mhz, uw = next(values)
            hz = int(re.search(r'opp-hz = /bits/ 64 <(\d+)>', text).group(1))
            if hz != mhz * 1000000:
                raise ValueError(f'{label}: OPP {hz} Hz, expected {mhz} MHz')
            return re.sub(r'(\n\t\t\tclock-latency-ns = <\d+>;)',
                          rf'\1\n\t\t\topp-microwatt = <{uw}>;', text, count=1)

        body = re.sub(r'\t\topp\d+ \{.*?\n\t\t\};', node, body, flags=re.S)
        if next(values, None) is not None:
            raise ValueError(f'{label}: fewer OPPs than derived')
        source = source[:start] + body + source[end:]
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--write', action='store_true', help=f'update {T602X.name}')
    args = parser.parse_args()
    if not T8112.exists():
        parser.error(f'{T8112} not found: set AURORA_TREE to a linux-aurora tree')
    derived = derive(T8112.read_text())
    for label, (coef, rms, table) in derived.items():
        print(f'{label}: a={coef[0]:.1f} b={coef[1]:.5f} rms {rms * 100:.1f}% '
              f'inefficient {inefficient(table) or "none"}')
        for mhz, uw in table:
            print(f'  {mhz} MHz: {uw} uW')
    if args.write:
        T602X.write_text(apply(T602X.read_text(), derived))
    return 0


if __name__ == '__main__':
    sys.exit(main())
