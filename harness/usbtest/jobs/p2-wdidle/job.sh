#!/bin/bash
# P2: does the loader's 120 s watchdog fire in the RAM root? Idle for 300 s, logging every 10 s. A reset near 120 s means the dog is live and nothing pets it; the summary's "away" time says which.
PUSH_TRIES=6
log "P2 kernel $(uname -r); wdt: $(ls /sys/class/watchdog 2>/dev/null | tr '\n' ' '); apple_wdt params: $(ls /sys/module/apple_wdt/parameters 2>/dev/null | tr '\n' ' ')"
push "P2 start" "$(tail -2 $LOG)"
for i in $(seq 1 30); do sleep 10; log "idle $((i*10)) s"; done
log "P2 survived 300 s idle"
