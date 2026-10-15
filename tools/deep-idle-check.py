#!/usr/bin/env python3
"""Report which deep-idle test is booted and whether it took effect.

  deep-idle-check.py [--seconds S]

Run it after booting one of the staged test images (E1 PMP, E4 no external
DCPs, E6 CPU energy model, or E1+E6) or the residency test kernel. It
names the m1n1 image by its sha256, then reports what that image should
change:

  device tree   CPU opp-microwatt entries, the pmp alias, the dcpext aliases
  energy model  the performance domains in debugfs, kernel.sched_energy_aware
  PMP           whether apple_pmp bound a device
  cpuidle       each state's disable setting, pd_residency_us if the kernel
                has it, and the share of time in WFI and CPU PD over S seconds
  domains       on/off of the display, ANE, USB-C and PMP power domains

It only reads. Without root the debugfs parts (energy model, domains) say
so and the rest still runs.
"""
import argparse
import hashlib
from pathlib import Path
import re
import sys
import time

BOOT_BIN = 'boot/m1n1/boot.bin'
DT = 'sys/firmware/devicetree/base'
CPUS = 'sys/devices/system/cpu'
RESIDENCY = 'sys/module/cpuidle_apple/parameters/pd_residency_us'
EAS = 'proc/sys/kernel/sched_energy_aware'
ENERGY_MODEL = 'sys/kernel/debug/energy_model'
GENPD_SUMMARY = 'sys/kernel/debug/pm_genpd/pm_genpd_summary'
PMP_DRIVER = 'sys/bus/platform/drivers/apple_pmp'
CMDLINE = 'proc/cmdline'

# sha256 prefixes of the images staged in ~/Work/deep-idle-build.
IMAGES = {
    '3630adc3b3be173c': 'stock (boot.bin.before-pmp-test)',
    'f09e39a996084b4b': 'E1 PMP (boot.bin.pmp-test)',
    'b69443cf3d9946f6': 'E4 no external DCPs (boot.bin.nodcpext-test)',
    '462a289d4ba0a2df': 'E6 CPU energy model (boot.bin.em-test)',
    'df7b49ba67743af5': 'E1+E6 PMP and energy model (boot.bin.pmp-em-test)',
}
DOMAINS = re.compile(r'^(disp0_|dispext\d_|ane_|atc\d_usb$|pmp$)')


def read(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeDecodeError):
        return None


def image(root):
    path = root / BOOT_BIN
    try:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    except OSError as error:
        return f'unreadable ({error.strerror})'
    return f'{digest} {IMAGES.get(digest, "not a staged image (rebuilt by update-m1n1?)")}'


def device_tree(root):
    dt = root / DT
    microwatts = sorted(dt.glob('opp-table-[01]/*/opp-microwatt'))
    aliases = dt / 'aliases'
    return [f'CPU opp-microwatt entries: {len(microwatts)} (23 with the energy model, 0 stock)',
            f'pmp alias: {"yes" if (aliases / "pmp").exists() else "no"}',
            'dcpext aliases: ' + (' '.join(name for name in ('dcpext0', 'dcpext1')
                                           if (aliases / name).exists()) or 'none')]


def energy_model(root):
    eas = read(root / EAS)
    if eas == '':
        eas = 'empty (EAS not possible)'
    lines = [f'sched_energy_aware: {eas if eas is not None else "?"}']
    em = root / ENERGY_MODEL
    try:
        domains = sorted(path.name for path in em.iterdir())
    except PermissionError:
        return lines + ['energy model: needs root']
    except OSError:
        return lines + ['energy model: no debugfs']
    lines.append(f'energy model domains: {" ".join(domains) or "none"}')
    return lines


def pmp(root):
    driver = root / PMP_DRIVER
    if not driver.exists():
        return ['apple_pmp: driver not registered']
    bound = sorted(path.name for path in driver.iterdir() if '.' in path.name and path.is_symlink())
    return [f'apple_pmp bound: {" ".join(bound) or "nothing"}']


def cpuidle_states(root):
    states = {}
    for state in sorted((root / CPUS).glob('cpu[0-9]*/cpuidle/state[0-9]*')):
        name = read(state / 'name')
        states.setdefault(name, []).append(state)
    return states


def residency(root):
    total = {}
    for name, states in cpuidle_states(root).items():
        total[name] = sum(int(read(state / 'time') or 0) for state in states)
    return total


def cpuidle(root, seconds, sleep=time.sleep, clock=time.monotonic):
    states = cpuidle_states(root)
    if not states:
        return ['cpuidle: no states']
    lines = []
    for name, paths in states.items():
        values = sorted({read(path / 'disable') for path in paths})
        lines.append(f'{name}: disable {"/".join(values)} on {len(paths)} CPUs')
    param = read(root / RESIDENCY)
    cmdline = read(root / CMDLINE) or ''
    given = re.search(r'cpuidle_apple\.pd_residency_us=(\S+)', cmdline)
    lines.append(f'pd_residency_us: {param if param else "not in this kernel"}'
                 + (f' (command line {given.group(1)})' if given else ''))
    cpus = len({path.parent.parent for paths in states.values() for path in paths})
    before, start = residency(root), clock()
    sleep(seconds)
    after, elapsed = residency(root), clock() - start
    span = elapsed * 1e6 * cpus
    if span > 0:
        lines.append('time over %gs: ' % seconds + ', '.join(
            f'{name} {100 * (after[name] - before[name]) / span:.1f}%' for name in after))
    return lines


def domains(root):
    try:
        text = (root / GENPD_SUMMARY).read_text()
    except PermissionError:
        return ['power domains: needs root']
    except OSError:
        return ['power domains: no debugfs']
    found = []
    for line in text.splitlines():
        if line[:1] in (' ', '-', '') or line.startswith('domain'):
            continue
        fields = line.split()
        if len(fields) >= 2 and DOMAINS.match(fields[0]):
            found.append(f'{fields[0]}={fields[1]}')
    return ['power domains: ' + (' '.join(found) or 'none of interest')]


def report(root, seconds, sleep=time.sleep, clock=time.monotonic):
    out = [f'kernel: {read(root / "proc/sys/kernel/osrelease")}', f'boot.bin: {image(root)}']
    for title, lines in (('device tree', device_tree(root)), ('energy model', energy_model(root)),
                         ('PMP', pmp(root)), ('cpuidle', cpuidle(root, seconds, sleep, clock)),
                         ('domains', domains(root))):
        out.append(f'{title}:')
        out.extend(f'  {line}' for line in lines)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--seconds', type=float, default=5, help='cpuidle sampling time')
    args = parser.parse_args()
    print('\n'.join(report(Path('/'), args.seconds)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
