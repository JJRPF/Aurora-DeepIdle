#!/usr/bin/env python3
# pmu-rtc.py: the Maverick PMU's RTC alarm, through the apple-spmi-nvmem file.
#   pmu-rtc.py show            registers, decoded
#   pmu-rtc.py test [secs]     arm an alarm secs ahead, poll the event bit and
#                              AIC HW_STATE for the nub-spmi0 lines, disarm
# Registers from the ADT spmi-mpmu node (info-rtc_*), semantics from
# AppleDialogSPMIPMURTC (Aurora-DeepIdle issue #5), alarm units checked here.
import os, struct, subprocess, sys, time

NV = "/sys/bus/nvmem/devices/spmi_nvmem0/nvmem"
CTRL, PMSET, RTC, ALARM, OFFSET = 0x1401, 0x1405, 0x1406, 0x140C, 0x1411
EVENT, IRQMASK = 0x14C0, 0x14C2
EN = 0x40
MMIO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mmio-read")
AIC_HW_STATE = 0x28E106800  # AIC2 die 0: 0x2000 + 4*4096 + 4*128*4
SPMI0_IRQS = [256, 724, 260, 261, 268, 269, 272, 273, 279, 280, 281, 282,
              283, 284, 285]


def rd(fd, off, n):
    return os.pread(fd, n, off)


def wr(fd, off, data):
    assert os.pwrite(fd, data, off) == len(data)


def secs(fd):
    # Reading 0x1406 latches the counter; bytes 2-5 are whole seconds.
    return struct.unpack("<I", rd(fd, RTC, 6)[2:])[0]


def hw_state():
    words = sorted({i // 32 for i in SPMI0_IRQS})
    hi = {}
    for w in words:
        out = subprocess.run([MMIO, hex(AIC_HW_STATE + 4 * w)],
                             capture_output=True, text=True, check=True)
        hi[w] = int(out.stdout.split()[1], 16)
    return [i for i in SPMI0_IRQS if hi[i // 32] >> (i % 32) & 1]


SPMI0 = 0x29E114000


def spmi_regs():
    out = subprocess.run([MMIO, hex(SPMI0 + 0x20), "0x1a"],
                         capture_output=True, text=True, check=True)
    w = [int(l.split()[1], 16) for l in out.stdout.splitlines()]
    return w[:9], w[16:25]  # mask 0x20-0x40, pending 0x60-0x80


def pend_bits():
    _, pend = spmi_regs()
    return [i * 32 + b for i, v in enumerate(pend) for b in range(32) if v >> b & 1]


def show(fd):
    ctrl, = rd(fd, CTRL, 1)
    al, = struct.unpack("<I", rd(fd, ALARM, 4))
    off = int.from_bytes(rd(fd, OFFSET, 6), "little")
    ev, mask = rd(fd, EVENT, 1)[0], rd(fd, IRQMASK, 1)[0]
    s = secs(fd)
    print(f"ctrl 0x{ctrl:02x} (enable {'on' if ctrl & EN else 'off'})  "
          f"event 0x{ev:02x}  irqmask 0x{mask:02x}")
    print(f"counter {s} s  alarm {al} s ({al - s:+d} s)  "
          f"unix(counter+offset) {s + (off >> 15)}  now {int(time.time())}")
    print("AIC HW_STATE high:", hw_state())
    mask, _ = spmi_regs()
    print("SPMI mask", " ".join(f"{v:08x}" for v in mask), " pending", pend_bits())


def test(fd, ahead):
    ctrl0 = rd(fd, CTRL, 1)[0]
    mask0 = rd(fd, IRQMASK, 1)[0]
    al0 = rd(fd, ALARM, 4)
    print("before:"); show(fd)
    t = secs(fd) + ahead
    try:
        wr(fd, CTRL, bytes([ctrl0 & ~EN]))
        if rd(fd, EVENT, 1)[0] & 1:
            wr(fd, EVENT, b"\x01")
        wr(fd, ALARM, struct.pack("<I", t))
        wr(fd, IRQMASK, bytes([mask0 & ~1]))
        wr(fd, CTRL, bytes([ctrl0 | EN]))
        print(f"armed for counter {t}"); show(fd)
        fired = None
        for _ in range(ahead + 20):
            time.sleep(1)
            s, ev, lines = secs(fd), rd(fd, EVENT, 1)[0], hw_state()
            print(f"  counter {s} ({s - t:+d})  ctrl 0x{rd(fd, CTRL, 1)[0]:02x}  event 0x{ev:02x}  AIC {lines}"
                  f"  SPMI pending {pend_bits()}")
            if ev & 1 and fired is None:
                fired = s
            if fired is not None and s >= fired + 3:
                break
        print("fired at" if fired else "no event", fired)
    finally:
        wr(fd, CTRL, bytes([ctrl0 & ~EN]))
        wr(fd, IRQMASK, bytes([mask0]))
        if rd(fd, EVENT, 1)[0] & 1:
            wr(fd, EVENT, b"\x01")
        wr(fd, ALARM, al0)
        wr(fd, CTRL, bytes([ctrl0]))
        print("restored:"); show(fd)


MMIO_W = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mmio-write")


def aic_all():
    out = subprocess.run([MMIO, hex(AIC_HW_STATE), "128"],
                         capture_output=True, text=True, check=True)
    w = [int(l.split()[1], 16) for l in out.stdout.splitlines()]
    return {i * 32 + b for i, v in enumerate(w) for b in range(32) if v >> b & 1}


def route(fd, ahead=8):
    """Fire the alarm, then unmask SPMI peripheral IRQ 2 briefly and diff
    the AIC's raw line state to find the line the controller drives."""
    ctrl0, mask0, al0 = rd(fd, CTRL, 1)[0], rd(fd, IRQMASK, 1)[0], rd(fd, ALARM, 4)
    m0, _ = spmi_regs()
    assert m0[0] == 0, "SPMI mask word 0 not zero; something else uses it"
    t = secs(fd) + ahead
    try:
        wr(fd, CTRL, bytes([ctrl0 & ~EN]))
        wr(fd, ALARM, struct.pack("<I", t))
        wr(fd, IRQMASK, bytes([mask0 & ~1]))
        wr(fd, CTRL, bytes([ctrl0 | EN]))
        while not rd(fd, EVENT, 1)[0] & 1:
            time.sleep(0.5)
        print("alarm fired at counter", secs(fd), "SPMI pending", pend_bits())
        base = aic_all()
        subprocess.run([MMIO_W, hex(SPMI0 + 0x20), "0x4"], check=True)
        time.sleep(0.2)
        hi = aic_all()
        print("AIC lines raised by unmasking SPMI irq 2:", sorted(hi - base),
              " dropped:", sorted(base - hi))
        subprocess.run([MMIO_W, hex(SPMI0 + 0x20), "0x0"], check=True)
        wr(fd, EVENT, b"\x01")
        subprocess.run([MMIO_W, hex(SPMI0 + 0x60), "0x4"], check=True)
        time.sleep(0.2)
        print("after re-mask and acks, still high from that set:",
              sorted((hi - base) & aic_all()))
    finally:
        subprocess.run([MMIO_W, hex(SPMI0 + 0x20), "0x0"], check=True)
        wr(fd, CTRL, bytes([ctrl0 & ~EN]))
        wr(fd, IRQMASK, bytes([mask0]))
        if rd(fd, EVENT, 1)[0] & 1:
            wr(fd, EVENT, b"\x01")
        wr(fd, ALARM, al0)
        wr(fd, CTRL, bytes([ctrl0]))
        print("restored:"); show(fd)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "show"
    fd = os.open(NV, os.O_RDWR if cmd == "test" else os.O_RDONLY)
    if cmd == "route":
        fd = os.open(NV, os.O_RDWR); route(fd)
    elif cmd == "test":
        test(fd, int(sys.argv[2]) if len(sys.argv) > 2 else 20)
    else:
        show(fd)
