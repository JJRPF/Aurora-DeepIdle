#!/usr/bin/env python3
"""Measure s2idle battery drain and what wakes the SoC while it sleeps.

  snapshot FILE   record the counters below in FILE (JSON)
  compare A B     report drain and wake activity between two snapshots
  around [FILE]   snapshot, suspend through systemd, snapshot after resume,
                  compare (and keep both snapshots in FILE if given)
  arm             snapshot into STATE and start the s2idle trace; then suspend
                  any way you like (lid, menu, systemctl)
  report          after resume: snapshot, compare with STATE, print the trace
                  analysis and stop the trace (--keep leaves it running)
  disarm          stop and remove the s2idle trace

Counters: the battery's energy (macsmc), the time spent suspended
(CLOCK_BOOTTIME - CLOCK_MONOTONIC), each CPU's s2idle entries per cpuidle
state, /proc/interrupts and, as root, the wakeup sources in debugfs. In
s2idle each CPU re-enters its idle state once per interrupt it takes, so
entries per suspended second measure how often the SoC woke.

As root it also records each power domain's power-off count (debugfs
pm_genpd), so the report lists the domains the kernel may power off (not
apple,always-on in the device tree) that stayed on through a suspend.

The s2idle trace is a tracefs instance of its own (INSTANCE). Triggers turn
it on when the machine enters suspend-to-idle and off at the first device
resume callback, so it holds only what happened while suspended: the
timekeeping freezes (each one a wake of the whole SoC), the interrupt that
woke the first CPU each time, and the interrupts, IPIs, timers and work that
ran. The trace clock stops while every CPU sleeps, so it orders events but
does not time the gaps between wakes.

It only reads, except that 'around' asks systemd to suspend and 'arm',
'report' and 'disarm' create, configure and remove the tracefs instance. Run
on battery: on AC the battery does not discharge and the drain is
meaningless.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

BATTERY = 'sys/class/power_supply/macsmc-battery'
CPUS = 'sys/devices/system/cpu'
WAKEUP_SOURCES = 'sys/kernel/debug/wakeup_sources'
GENPD = 'sys/kernel/debug/pm_genpd'
PMGR = 'sys/firmware/devicetree/base/soc'
TRACING = 'sys/kernel/tracing'
INSTANCE = 'sleep-drain-probe'
STATE = Path('/var/tmp/sleep-drain-probe.json')

TRACE_EVENTS = (
    'power/suspend_resume',
    'power/wakeup_source_activate',
    'irq/irq_handler_entry',
    'irq/softirq_entry',
    'ipi/ipi_entry',
    'timer/hrtimer_expire_entry',
    'timer/timer_expire_entry',
    'workqueue/workqueue_execute_start',
)
# An event takes one traceon/traceoff trigger, so the trace stops at the
# first device callback after suspend-to-idle (system sleep callbacks are
# the only ones this event traces; the ones before it find the trace off).
TRACE_TRIGGERS = (
    ('power/suspend_resume', 'traceon if action == "machine_suspend" && start == 1'),
    ('power/device_pm_callback_start', 'traceoff'),
)


def read(path, default=None):
    try:
        return path.read_text().strip()
    except OSError:
        return default


def read_int(path):
    value = read(path)
    return int(value) if value is not None and value.lstrip('-').isdigit() else None


def interrupts(text):
    """Total count per interrupt line of /proc/interrupts, keyed 'irq name'."""
    lines = text.splitlines()
    if not lines:
        return {}
    ncpus = len(lines[0].split())
    counts = {}
    for line in lines[1:]:
        irq, _, rest = line.partition(':')
        fields = rest.split()
        cells = [int(f) for f in fields[:ncpus] if f.isdigit()]
        if not cells:
            continue
        name = ' '.join(fields[len(cells):])
        counts[f'{irq.strip()} {name}'.strip()] = sum(cells)
    return counts


def wakeup_sources(text):
    rows = text.splitlines()
    sources = {}
    for row in rows[1:]:
        fields = row.split()
        if len(fields) >= 4 and fields[2].isdigit() and fields[3].isdigit():
            sources[fields[0]] = {'events': int(fields[2]), 'wakeups': int(fields[3])}
    return sources


def genpd(root):
    """Power-off count (all idle states' usage) and state of each domain."""
    base = root / GENPD
    try:
        names = sorted(path.name for path in base.iterdir())
    except OSError:
        return None
    domains = {}
    for name in names:
        rows = (read(base / name / 'idle_states') or '').splitlines()[1:]
        usage = [row.split() for row in rows]
        domains[name] = {
            'off': sum(int(f[2]) for f in usage if len(f) > 2 and f[2].isdigit()),
            'state': (read(base / name / 'current_state') or '?').split('-')[0],
        }
    return domains


def always_on(root):
    """Labels of the PMGR power states the device tree keeps always on."""
    return sorted(read(node / 'label', '').rstrip('\0')
                  for node in (root / PMGR).glob('power-management@*/power-controller@*')
                  if (node / 'apple,always-on').exists())


def snapshot(root=Path('/')):
    cpus = {}
    for cpu in sorted((root / CPUS).glob('cpu[0-9]*')):
        states = {}
        for state in sorted((cpu / 'cpuidle').glob('state[0-9]*')):
            states[read(state / 'name', state.name)] = read_int(state / 's2idle' / 'usage')
        cpus[cpu.name] = states
    battery = root / BATTERY
    sources = read(root / WAKEUP_SOURCES)
    return {
        'wall': time.time(),
        'monotonic': time.clock_gettime(time.CLOCK_MONOTONIC),
        'boottime': time.clock_gettime(time.CLOCK_BOOTTIME),
        'battery': {
            'status': read(battery / 'status'),
            'energy_uwh': read_int(battery / 'energy_now'),
            'capacity': read_int(battery / 'capacity'),
        },
        'cpus': cpus,
        'interrupts': interrupts(read(root / 'proc/interrupts', '')),
        'wakeup_sources': wakeup_sources(sources) if sources else None,
        'suspend_success': read_int(root / 'sys/power/suspend_stats/success'),
        'mem_sleep': read(root / 'sys/power/mem_sleep'),
        'genpd': genpd(root),
        'always_on': always_on(root),
    }


def compare(a, b, top=12):
    """The report between snapshots a and b, as lines of text."""
    suspended = max(0.0, (b['boottime'] - b['monotonic']) - (a['boottime'] - a['monotonic']))
    awake = b['monotonic'] - a['monotonic']
    total = b['boottime'] - a['boottime']
    out = [f'window {total / 3600:.2f} h: suspended {suspended / 3600:.2f} h, '
           f'awake {awake / 60:.1f} min; suspends '
           f'{(b["suspend_success"] or 0) - (a["suspend_success"] or 0)}; '
           f'mem_sleep {b["mem_sleep"]}']

    ea, eb = a['battery']['energy_uwh'], b['battery']['energy_uwh']
    if ea is None or eb is None:
        out.append('battery: no energy reading')
    else:
        used = (ea - eb) / 1e6
        out.append(f'battery: {ea / 1e6:.2f} -> {eb / 1e6:.2f} Wh ({used:.3f} Wh used), '
                   f'status {a["battery"]["status"]} -> {b["battery"]["status"]}')
        if total > 0:
            out.append(f'average drain over the window: {used / (total / 3600):.3f} W')
        if 'Discharging' not in (a['battery']['status'], b['battery']['status']):
            out.append('warning: the battery was not discharging; this drain is not the '
                       'sleep drain (run on battery)')
        if suspended > 0 and awake > 0.05 * total:
            out.append('note: the awake time is more than 5% of the window, so the '
                       'average overstates the sleep drain')

    if suspended > 1:
        out.append('s2idle entries per suspended second (each is one wake of that CPU):')
        for cpu, states in b['cpus'].items():
            before = a['cpus'].get(cpu, {})
            deltas = {name: (count or 0) - (before.get(name) or 0)
                      for name, count in states.items()}
            entries = sum(deltas.values())
            detail = ', '.join(f'{name} {count}' for name, count in deltas.items() if count)
            out.append(f'  {cpu}: {entries / suspended:8.2f}/s  ({detail or "none"})')

    deltas = sorted(((b['interrupts'][irq] - a['interrupts'].get(irq, 0), irq)
                     for irq in b['interrupts']), reverse=True)
    out.append(f'interrupts over the window (top {top}; includes the awake time):')
    for count, irq in deltas[:top]:
        if count <= 0:
            break
        rate = f' ({count / suspended:.2f} per suspended s)' if suspended > 1 else ''
        out.append(f'  {count:10d} {irq}{rate}')

    if a['wakeup_sources'] is not None and b['wakeup_sources'] is not None:
        changed = []
        for name, now in b['wakeup_sources'].items():
            then = a['wakeup_sources'].get(name, {'events': 0, 'wakeups': 0})
            events = now['events'] - then['events']
            wakeups = now['wakeups'] - then['wakeups']
            if events or wakeups:
                changed.append((events, wakeups, name))
        out.append('wakeup sources (events, wakeups):')
        out.extend(f'  {events:6d} {wakeups:6d} {name}'
                   for events, wakeups, name in sorted(changed, reverse=True)[:top])
        if not changed:
            out.append('  none')
    else:
        out.append('wakeup sources: not read (run as root)')

    suspends = (b['suspend_success'] or 0) - (a['suspend_success'] or 0)
    if a.get('genpd') and b.get('genpd') and suspends > 0:
        fixed = set(b.get('always_on') or ())
        stayed = sorted(name for name, now in b['genpd'].items()
                        if name in a['genpd'] and name not in fixed
                        and 'on' in (a['genpd'][name]['state'], now['state'])
                        and now['off'] - a['genpd'][name]['off'] < suspends)
        out.append(f'power domains not always-on that stayed on through a suspend '
                   f'({len(stayed)}; {len(fixed)} always-on domains not listed):')
        out.append('  ' + (' '.join(stayed) or 'none'))
    elif suspends > 0:
        out.append('power domains: not read (run as root)')
    return out


TRACE_LINE = re.compile(r'^\s*.+?-\d+\s+\[(?P<cpu>\d+)\]\s+(?:\S+\s+)?[\d.]+:\s+'
                        r'(?P<event>\w+):\s+(?P<body>.*)$')
TRACE_KEYS = {
    'irq_handler_entry': re.compile(r'name=(\S+)'),
    'ipi_entry': re.compile(r'\((.*)\)'),
    'softirq_entry': re.compile(r'action=(\w+)'),
    'hrtimer_expire_entry': re.compile(r'function=(\S+)'),
    'timer_expire_entry': re.compile(r'function=(\S+)'),
    'workqueue_execute_start': re.compile(r'function (\S+)'),
    'wakeup_source_activate': re.compile(r'^(\S+)'),
}
TRACE_NAMES = {
    'irq_handler_entry': 'interrupts',
    'ipi_entry': 'IPIs',
    'softirq_entry': 'softirqs',
    'hrtimer_expire_entry': 'hrtimers',
    'timer_expire_entry': 'timers',
    'workqueue_execute_start': 'work items',
    'wakeup_source_activate': 'wakeup sources activated',
}


def analyse_trace(text, top=10):
    """Report on an s2idle trace, as lines of text.

    Each 'timekeeping_freeze[N] end' marks CPU N leaving a state in which
    every CPU slept; the next interrupt or IPI that CPU takes is what woke
    the SoC.
    """
    freezes, woken, counts = 0, Counter(), {event: Counter() for event in TRACE_KEYS}
    waiting = set()
    written = None
    for line in text.splitlines():
        if line.startswith('#'):
            match = re.search(r'entries-in-buffer/entries-written: (\d+)/(\d+)', line)
            if match:
                written = tuple(int(n) for n in match.groups())
            continue
        match = TRACE_LINE.match(line)
        if not match:
            continue
        cpu, event, body = int(match['cpu']), match['event'], match['body']
        if event == 'suspend_resume':
            if body.startswith('timekeeping_freeze[') and body.endswith(' end'):
                freezes += 1
                waiting.add(cpu)
            continue
        key = TRACE_KEYS.get(event)
        if not key:
            continue
        found = key.search(body)
        name = found.group(1) if found else body
        counts[event][name] += 1
        # An IPI also enters as an interrupt named IPI; its ipi_entry names it.
        if cpu in waiting and (event == 'ipi_entry' or
                               event == 'irq_handler_entry' and name != 'IPI'):
            waiting.discard(cpu)
            woken[f'{"IPI " if event == "ipi_entry" else ""}{name}'] += 1

    out = [f's2idle trace: {freezes} whole-SoC wakes']
    if written and written[1] > written[0]:
        out.append(f'warning: the trace buffer filled: kept the first {written[0]} of '
                   f'{written[1]} events (arm with a larger --buffer-kb)')
    if freezes:
        out.append('what woke the SoC (first interrupt on the waking CPU):')
        out.extend(f'  {count:8d} {100 * count / freezes:5.1f}%  {name}'
                   for name, count in woken.most_common(top))
        unknown = freezes - sum(woken.values())
        if unknown:
            out.append(f'  {unknown:8d} {100 * unknown / freezes:5.1f}%  (no interrupt traced)')
    for event, title in TRACE_NAMES.items():
        if counts[event]:
            per = ', per wake' if freezes else ''
            out.append(f'{title} while suspended (count{per}):')
            out.extend(f'  {count:8d}' + (f' {count / freezes:7.2f}' if freezes else '')
                       + f'  {name}' for name, count in counts[event].most_common(top))
    return out


def write(path, value):
    path.write_text(value + '\n')


def arm_trace(root=Path('/'), buffer_kb=8192):
    instance = root / TRACING / 'instances' / INSTANCE
    instance.mkdir()
    try:
        write(instance / 'tracing_on', '0')
        write(instance / 'buffer_size_kb', str(buffer_kb))
        # Keep the first events of a long sleep rather than the last.
        write(instance / 'options/overwrite', '0')
        for event in TRACE_EVENTS:
            write(instance / 'events' / event / 'enable', '1')
        for event, trigger in TRACE_TRIGGERS:
            write(instance / 'events' / event / 'trigger', trigger)
    except OSError:
        disarm_trace(root)
        raise


def disarm_trace(root=Path('/')):
    instance = root / TRACING / 'instances' / INSTANCE
    if not instance.exists():
        return False
    write(instance / 'tracing_on', '0')
    for event, trigger in TRACE_TRIGGERS:
        try:
            write(instance / 'events' / event / 'trigger', '!' + trigger)
        except OSError:
            pass
    for event in TRACE_EVENTS:
        try:
            write(instance / 'events' / event / 'enable', '0')
        except OSError:
            pass
    instance.rmdir()
    return True


def around(wait_for_suspend=120, settle=5):
    before = snapshot()
    subprocess.run(['systemctl', 'suspend'], check=True)
    offset = before['boottime'] - before['monotonic']
    deadline = time.monotonic() + wait_for_suspend
    while time.monotonic() < deadline:
        time.sleep(1)
        if time.clock_gettime(time.CLOCK_BOOTTIME) - \
                time.clock_gettime(time.CLOCK_MONOTONIC) - offset > 2:
            break
    else:
        print(f'warning: no suspend seen within {wait_for_suspend} s', file=sys.stderr)
    # The SMC updates the battery reading a few seconds after resume.
    time.sleep(settle)
    return before, snapshot()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    take = sub.add_parser('snapshot')
    take.add_argument('file', type=Path)
    diff = sub.add_parser('compare')
    diff.add_argument('before', type=Path)
    diff.add_argument('after', type=Path)
    wrap = sub.add_parser('around')
    wrap.add_argument('file', type=Path, nargs='?')
    arm = sub.add_parser('arm')
    arm.add_argument('--buffer-kb', type=int, default=8192,
                     help='trace buffer per CPU (default 8192)')
    report = sub.add_parser('report')
    report.add_argument('--keep', action='store_true',
                        help='leave the trace running for another suspend')
    sub.add_parser('disarm')
    args = parser.parse_args()

    if args.command in ('arm', 'report', 'disarm') and os.geteuid() != 0:
        parser.error(f'{args.command} needs root (tracefs and debugfs)')
    if args.command == 'arm':
        if (Path('/') / TRACING / 'instances' / INSTANCE).exists():
            parser.error('already armed: run report or disarm first')
        STATE.write_text(json.dumps({'before': snapshot()}))
        arm_trace(buffer_kb=args.buffer_kb)
        print(f'armed: counters in {STATE}, trace in {TRACING}/instances/{INSTANCE}.\n'
              'Suspend as usual, on battery; after resume run: report')
        return 0
    if args.command == 'disarm':
        print('disarmed' if disarm_trace() else 'not armed')
        return 0
    if args.command == 'report':
        a = json.loads(STATE.read_text())['before']
        b = snapshot()
        STATE.write_text(json.dumps({'before': a, 'after': b}))
        print('\n'.join(compare(a, b)))
        trace = read(Path('/') / TRACING / 'instances' / INSTANCE / 'trace')
        if trace is None:
            print('s2idle trace: not armed')
        else:
            print('\n'.join(analyse_trace(trace)))
            if not args.keep:
                disarm_trace()
        return 0

    if args.command == 'snapshot':
        args.file.write_text(json.dumps(snapshot()))
        return 0
    if args.command == 'compare':
        a, b = (json.loads(path.read_text()) for path in (args.before, args.after))
    else:
        a, b = around()
        if args.file:
            args.file.write_text(json.dumps({'before': a, 'after': b}))
    print('\n'.join(compare(a, b)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
