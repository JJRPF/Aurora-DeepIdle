#!/usr/bin/env python3
"""Compare CPU idle settings by system power, on a running machine.

  idle-ab.py [--rounds N] [--window S] [--settle S] SETTING...

Each SETTING is one of
  default      both states enabled, the residency as found
  wfi-only     CPU PD disabled
  pd-always    WFI disabled, so every idle entry is CPU PD
  res=US       both states enabled, CPU PD target residency US microseconds
               (needs cpuidle_apple.pd_residency_us)
  no-eas       both states enabled, energy-aware scheduling off
               (kernel.sched_energy_aware=0; needs a CPU energy model,
               so compare it with default to see what EAS saves)

wfi-only and pd-always take a CPU list, as in pd-always@4-9 or
wfi-only@0,2: the listed CPUs get the setting and the others both states,
to tell the E cores' share from the P cores' or one cluster's.

Every round runs each setting for --window seconds, after --settle seconds,
alternating the order from round to round, and samples every SMC power
sensor once a second (Total System Power, and Heatpipe Power, the SoC
package, which leaves out the display and the rest of the board). The report
gives each setting's mean per sensor, its CPU PD and WFI residency, and its
difference from the first setting, paired by round: a busy machine's load
drifts by watts, and pairing cancels most of it. More rounds narrow the
spread (the standard error is printed). It also gives each setting's busy
time (all CPUs, from /proc/stat) and each cpufreq policy's mean frequency,
to show whether a setting changed the work done or the clocks rather than
only the idle power.

It writes only the cpuidle 'disable' files, pd_residency_us and
sched_energy_aware, as root, and puts every one back as it found it on
exit, also on an error or Ctrl-C.
"""
import argparse
import json
from pathlib import Path
import statistics
import sys
import time

CPUS = 'sys/devices/system/cpu'
HWMON = 'sys/class/hwmon'
RESIDENCY = 'sys/module/cpuidle_apple/parameters/pd_residency_us'
EAS = 'proc/sys/kernel/sched_energy_aware'
POWER_LABEL = 'Total System Power'
POLICIES = 'sys/devices/system/cpu/cpufreq'
STAT = 'proc/stat'
HWMON_NAME = 'macsmc_hwmon'


def parse_cpus(text):
    """The set of CPU numbers in a list such as 0-3,7."""
    cpus = set()
    for part in text.split(','):
        first, _, last = part.partition('-')
        if not first.isdigit() or not (last or first).isdigit() or int(first) > int(last or first):
            raise ValueError(f'bad CPU list {text!r}')
        cpus.update(range(int(first), int(last or first) + 1))
    return frozenset(cpus)


def parse_setting(text):
    """(state0 disable, state1 disable, residency or None, CPUs or None, EAS or None)
    for a SETTING."""
    fixed = {'default': (0, 0), 'wfi-only': (0, 1), 'pd-always': (1, 0)}
    name, at, cpus = text.partition('@')
    if name in fixed and not (at and name == 'default'):
        return (*fixed[name], None, parse_cpus(cpus) if at else None, None)
    if text.startswith('res=') and text[4:].isdigit() and int(text[4:]) > 0:
        return 0, 0, int(text[4:]), None, None
    if text == 'no-eas':
        return 0, 0, None, None, 0
    raise ValueError(f'unknown setting {text!r}')


def power_sensors(root):
    """{label: input path} of the SMC's power sensors, Total System Power first."""
    sensors = {}
    for label in sorted((root / HWMON).glob('hwmon*/power*_label')):
        name = (label.parent / 'name').read_text().strip() if (label.parent / 'name').exists() else ''
        if name == HWMON_NAME or label.read_text().strip() == POWER_LABEL:
            sensors[label.read_text().strip()] = label.with_name(
                label.name.replace('_label', '_input'))
    if POWER_LABEL not in sensors:
        raise FileNotFoundError(f'no hwmon sensor labelled {POWER_LABEL!r}')
    return dict(sorted(sensors.items(), key=lambda item: item[0] != POWER_LABEL))


class Machine:
    def __init__(self, root=Path('/')):
        self.root = root
        self.cpus = sorted((root / CPUS).glob('cpu[0-9]*/cpuidle'),
                           key=lambda path: int(path.parent.name[3:]))
        if not self.cpus:
            raise FileNotFoundError('no cpuidle states')
        self.sensors = power_sensors(root)
        self.residency = root / RESIDENCY
        self.eas = root / EAS
        self.policies = sorted((root / POLICIES).glob('policy[0-9]*'),
                               key=lambda path: int(path.name[6:]))
        self.saved = {path: path.read_text() for path in self.knobs()}
        self.written = set()

    def knobs(self):
        paths = [cpu / f'state{i}/disable' for cpu in self.cpus for i in (0, 1)]
        return paths + [path for path in (self.residency, self.eas) if path.exists()]

    def apply(self, setting):
        d0, d1, residency, only, eas = setting
        if eas is not None:
            if not self.eas.exists():
                raise FileNotFoundError(f'{EAS} is missing')
            self.write(self.eas, f'{eas}\n')
        elif self.eas in self.written:
            # Each write rebuilds the scheduler domains; leave it alone until used.
            self.write(self.eas, self.saved[self.eas])
        if residency is not None:
            if not self.residency.exists():
                raise FileNotFoundError(f'{RESIDENCY} is missing: this kernel has no '
                                        'pd_residency_us')
            self.write(self.residency, f'{residency}\n')
        elif self.residency in self.saved:
            self.write(self.residency, self.saved[self.residency])
        for number, cpu in zip(self.numbers(), self.cpus):
            mine = only is None or number in only
            self.write(cpu / 'state0/disable', f'{d0 if mine else 0}\n')
            self.write(cpu / 'state1/disable', f'{d1 if mine else 0}\n')

    def write(self, path, value):
        self.written.add(path)
        path.write_text(value)

    def numbers(self):
        return [int(cpu.parent.name[3:]) for cpu in self.cpus]

    def restore(self):
        """Put back every knob this run wrote."""
        for path, value in self.saved.items():
            if path in self.written:
                path.write_text(value)

    def residency_us(self):
        """Time in WFI and in CPU PD of each CPU, in microseconds."""
        return [[int((cpu / f'state{i}/time').read_text()) for i in (0, 1)] for cpu in self.cpus]

    def busy(self):
        """{CPU number: (busy, total)} jiffies, busy being all but idle and iowait."""
        out = {}
        for line in (self.root / STAT).read_text().splitlines():
            fields = line.split()
            if fields and fields[0].startswith('cpu') and fields[0][3:].isdigit():
                ticks = [int(x) for x in fields[1:]]
                out[int(fields[0][3:])] = (sum(ticks) - ticks[3] - ticks[4], sum(ticks))
        return out

    def mhz(self):
        """{policy name: current MHz}."""
        return {policy.name: int((policy / 'scaling_cur_freq').read_text()) // 1000
                for policy in self.policies}

    def watts(self):
        """{label: watts} for every sensor."""
        return {label: int(path.read_text()) / 1e6 for label, path in self.sensors.items()}


def run(machine, names, rounds, window, settle, log=None):
    for name in names:
        only = parse_setting(name)[3]
        if only is not None and not only <= set(machine.numbers()):
            raise ValueError(f'{name}: no CPU {min(only - set(machine.numbers()))}')
    rows = []
    try:
        for n in range(rounds):
            for name in (names if n % 2 == 0 else names[::-1]):
                machine.apply(parse_setting(name))
                time.sleep(settle)
                before, start, samples = machine.residency_us(), time.monotonic(), []
                ticks, clocks = machine.busy(), []
                while time.monotonic() - start < window:
                    samples.append(machine.watts())
                    clocks.append(machine.mhz())
                    time.sleep(1)
                after, elapsed = machine.residency_us(), time.monotonic() - start
                ticks = {cpu: [b - a for a, b in zip(ticks[cpu], now)]
                         for cpu, now in machine.busy().items() if cpu in ticks}
                busy, jiffies = (sum(t[i] for t in ticks.values()) for i in (0, 1))
                spent = [[a - b for a, b in zip(*pair)] for pair in zip(after, before)]
                total = elapsed * 1e6 * len(machine.cpus)
                row = {'round': n, 'setting': name,
                       'watts': statistics.mean(sample[POWER_LABEL] for sample in samples),
                       'sensors': {label: statistics.mean(sample[label] for sample in samples)
                                   for label in samples[0]},
                       'wfi_pct': 100 * sum(cpu[0] for cpu in spent) / total,
                       'pd_pct': 100 * sum(cpu[1] for cpu in spent) / total,
                       'pd_pct_by_cpu': {number: round(100 * cpu[1] / (elapsed * 1e6), 1)
                                         for number, cpu in zip(machine.numbers(), spent)},
                       'busy_pct': 100 * busy / jiffies if jiffies else 0.0,
                       'busy_pct_by_cpu': {cpu: round(100 * b / t, 1) if t else 0.0
                                           for cpu, (b, t) in ticks.items()},
                       'mhz': {name: statistics.mean(clock[name] for clock in clocks)
                               for name in clocks[0]}}
                rows.append(row)
                if log:
                    print(json.dumps(row), file=log, flush=True)
    finally:
        machine.restore()
    return rows


def report(rows, names):
    out = []
    labels = list(rows[0].get('sensors') or {POWER_LABEL: None}) if rows else []
    for label in labels:
        def watts(row):
            return row['sensors'][label] if 'sensors' in row else row['watts']
        out.append(f'{label}:')
        out.append(f'  {"setting":12} {"mean W":>8} {"PD %":>6} {"WFI %":>6}   '
                   f'paired difference from {names[0]}')
        base = {row['round']: watts(row) for row in rows if row['setting'] == names[0]}
        for name in names:
            mine = [row for row in rows if row['setting'] == name]
            if not mine:
                continue
            line = (f'  {name:12} {statistics.mean(watts(r) for r in mine):8.2f} '
                    f'{statistics.mean(r["pd_pct"] for r in mine):6.1f} '
                    f'{statistics.mean(r["wfi_pct"] for r in mine):6.1f}')
            diffs = [watts(r) - base[r['round']] for r in mine if r['round'] in base]
            if name != names[0] and len(diffs) > 1:
                mean, sd = statistics.mean(diffs), statistics.stdev(diffs)
                lower = sum(d < 0 for d in diffs)
                line += (f'   {mean:+.3f} W (sd {sd:.2f}, se {sd / len(diffs) ** 0.5:.3f}, '
                         f'lower in {lower} of {len(diffs)})')
            out.append(line)
    if rows and 'busy_pct' in rows[0]:
        out.append('Busy time and clocks:')
        policies = list(rows[0]['mhz'])
        out.append(f'  {"setting":12} {"busy %":>6} ' + ' '.join(f'{name:>9}' for name in policies))
        for name in names:
            mine = [row for row in rows if row['setting'] == name]
            if mine:
                out.append(f'  {name:12} {statistics.mean(r["busy_pct"] for r in mine):6.1f} ' +
                           ' '.join(f'{statistics.mean(r["mhz"][p] for r in mine):9.0f}'
                                    for p in policies))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--rounds', type=int, default=10)
    parser.add_argument('--window', type=int, default=20, help='seconds per setting')
    parser.add_argument('--settle', type=int, default=3, help='seconds before sampling')
    parser.add_argument('--log', type=Path, help='also write each window as JSON lines')
    parser.add_argument('settings', nargs='+')
    args = parser.parse_args()
    for name in args.settings:
        try:
            parse_setting(name)
        except ValueError as error:
            parser.error(str(error))
    if len(set(args.settings)) != len(args.settings):
        parser.error('each setting once')
    machine = Machine()
    log = args.log.open('w') if args.log else None
    rows = run(machine, args.settings, args.rounds, args.window, args.settle, log)
    print('\n'.join(report(rows, args.settings)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
