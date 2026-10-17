#!/bin/bash
# Battery gauge log for the PMP before/after steps: epoch power_now(uW) current_now(uA) voltage_now(uV) energy_now(uWh)
B=/sys/class/power_supply/macsmc-battery
out=${1:?output file}
while :; do
    echo "$(date +%s) $(cat $B/power_now $B/current_now $B/voltage_now $B/energy_now | tr '\n' ' ')" >> "$out"
    sleep 10
done
