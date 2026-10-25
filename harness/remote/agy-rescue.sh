#!/bin/bash
# Pi side: the helper the Mac guard calls when the Mac stays unreachable. agy (Gemini 3.8 Flash, high)
# reads the logs and writes a diagnosis report. It does NOT take over the project: the Claude Code
# session on the Mac resumes at the next Linux boot and reads the report.
D=$HOME/deepidle; mkdir -p "$D/rescue"
R=$D/rescue/$(date +%Y%m%d-%H%M%S).md
LASTRUN=$(ls -dt "$D"/hv/*/ 2>/dev/null | head -1)
PROMPT="You are a helper on a Raspberry Pi that controls an Apple M2 Pro Mac (J414s) running Aura (a fork of m1n1) under test. The Mac has been unreachable for a long time. You are NOT the project agent and you do not continue the project. Do only this:
1. Read: $D/guard.log (tail 60), the newest files in $D/watch/ (the Mac's kernel log and ping log, tail 80 each), and ${LASTRUN}run.txt and the tail of ${LASTRUN}console.txt.
2. Check whether /dev/m1n1 exists and lsusb shows the Mac. If /dev/m1n1 exists, you may run: cd $D/aura/proxyclient && timeout 60 python3 tools/reboot.py < /dev/null. Nothing else on the Mac: no register writes, no other proxy tools, no ssh commands that change anything.
3. Write a short report to $R: what state the Mac seems to be in, what you did, and what the owner must do (for example press the power key; you cannot). Never print the Pi's username or any path containing it, and never print IP addresses. Do not edit any other file."
timeout 900 "$HOME/.local/bin/agy" --model gemini-3.8-flash-high --effort high --dangerously-skip-permissions \
    --print-timeout 600s -p "$PROMPT" >> "$D/rescue/agy-last.txt" 2>&1
echo "$(date '+%F %T') agy-rescue finished, report: $R"
