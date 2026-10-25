#!/usr/bin/env python3
"""Pi side: keep an interactive agy session alive in remote-control (RC) mode, in a pty with no terminal
attached, so the owner can attach from the agy app/site at any time and the helper is ready when a test
strands the Mac. Output goes to ~/deepidle/rescue/agy-session.log; it restarts agy if it exits.
  agy-session.py start | stop | status
It is the standing helper, not the project agent: its prompt says so."""
import os, pty, sys, time, signal, select, subprocess
D = os.path.expanduser("~/deepidle"); R = D + "/rescue"; PIDF = R + "/agy-session.pid"
LOG = R + "/agy-session.log"; AGY = os.path.expanduser("~/.local/bin/agy")
PROMPT = ("You are the standing rescue helper on a Raspberry Pi that drives an Apple M2 Pro Mac (J414s) running Aura "
          "(an m1n1 fork) under test. You are NOT the project agent; the Claude Code session on the Mac continues the project. "
          "Wait for instructions through remote control. If asked to recover the Mac: cd ~/deepidle/aura/proxyclient && "
          "timeout 60 python3 tools/reboot.py < /dev/null (only that, no register writes). Keep a log of everything you do in "
          "~/deepidle/rescue/agy-actions.log, one line per action with a timestamp. Never print the Pi's login or any path "
          "containing it, and no IP addresses. The macOSTest guest login is in ~/deepidle/secret/macostest-login (the owner "
          "allows its use on that volume only).")
def alive(pid):
    try: os.kill(pid, 0); return True
    except OSError: return False
def run():
    os.makedirs(R, exist_ok=True)
    open(PIDF, "w").write(str(os.getpid()))
    stop = []
    signal.signal(signal.SIGTERM, lambda *a: stop.append(1))
    log = open(LOG, "ab", buffering=0)
    while not stop:
        log.write(time.strftime("\n--- %F %T starting agy\n").encode())
        pid, fd = pty.fork()
        if pid == 0:
            os.environ["TERM"] = "xterm-256color"
            os.execv(AGY, [AGY, "--remote-control", "--model", "gemini-3.8-flash-high", "--effort", "high",
                           "--dangerously-skip-permissions", "-i", PROMPT])
        os.set_blocking(fd, False)
        while not stop and alive(pid):
            r, _, _ = select.select([fd], [], [], 5)
            if r:
                try: data = os.read(fd, 65536)
                except OSError: break
                if not data: break
                log.write(data)
        try: os.kill(pid, signal.SIGTERM); os.waitpid(pid, 0)
        except OSError: pass
        log.write(time.strftime("\n--- %F %T agy exited\n").encode())
        if not stop: time.sleep(15)
cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
if cmd == "_run": run()
elif cmd == "start":
    if os.path.exists(PIDF) and alive(int(open(PIDF).read() or 0)): print("already running"); sys.exit(0)
    subprocess.Popen([sys.executable, __file__, "_run"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(2); print("started")
elif cmd == "stop":
    if os.path.exists(PIDF): os.kill(int(open(PIDF).read()), signal.SIGTERM); os.remove(PIDF)
    print("stopped")
else:
    ok = os.path.exists(PIDF) and alive(int(open(PIDF).read() or 0))
    up = subprocess.run(["pgrep", "-f", "agy.*--remote-control"], capture_output=True).returncode == 0
    print("session supervisor:", "running" if ok else "not running", "| agy process:", "up" if up else "down")
