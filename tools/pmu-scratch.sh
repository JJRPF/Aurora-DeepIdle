#!/bin/bash
# Reads the PMU's legacy scratch keys (0x6000-0x601f) and decodes Aura's S2R crumbs (aura-ctl bit 0x4000, psci.c
# qs_crumb_snapshot). Run on main after a commit run that ended in a reset:  sudo bash tools/pmu-scratch.sh [zero]
# zero: clear Aura's keys afterwards (0x6004-0x6007, 0x600c-0x600e, 0x6011-0x6016, 0x601b-0x601e). 0x6010 is the
# one-shot loader's flag and 0x6017 is not ours: both are left alone.
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
[ -r "$N" ] || { echo "no PMU nvmem (run with sudo)"; exit 1; }
B=($(dd if=$N bs=1 skip=$((0x6000)) count=32 2>/dev/null | xxd -p -c1))
echo "raw 0x6000-0x601f: ${B[*]}"
b() { echo "${B[$((0x$1 - 0x6000))]}"; }
case $(b 6004) in
    00) S="none (no crumb run, or zeroed)" ;; 11) S="entry" ;; 12) S="records taken" ;; 13) S="S2R timer written" ;;
    14) S="WD2 stopped" ;; 15) S="AIC masked" ;; 16) S="quiet commit: last access before the commit (expected for a commit run)" ;;
    17) S="before the secondaries are released" ;; 18|19) S="non-quiet path: after the snapshot. Image 68 commit run: 18 = stopped in the SEP step, 19 = SEP step done, stopped in the PMGR quiesce" ;;
    1e|22) S="RESUME path reached (Aura returned to the kernel)" ;; 21) S="resume: undo done" ;; *) S="?" ;;
esac
echo "0x6004 last stage      $(b 6004): $S"
echo "0x6005/6 CPU_OFF mask  $(b 6006)$(b 6005)   0x6007 first never-slept core $(b 6007) (ff = every core slept)"
echo "0x6015/6 never-slept   $(b 6016)$(b 6015)   0x6014 wait for the P complexes $(b 6014) (x 2 ms, ff = timeout)"
echo "0x6012/13/1b ECPM PCPM0 PCPM1 power words >> 4: $(b 6012) $(b 6013) $(b 601b)"
echo "0x601c-1e EACC PACC0 PACC1 cluster words: $(b 601c) $(b 601d) $(b 601e)"
echo "0x600c PCIe/AON still on $(b 600c) (image 64, bits 0-2 apcie_gp_sys gpshr_sys gp, 3-6 atc1-3_usb_aon msg, 7 an ATC word; ff = step not run)"
echo "0x600d, 0x600e           $(b 600d) $(b 600e) (fabric, ATC: they read 0 after every reset, only valid without one)"
echo "0x6011 PMP, SEP           $(b 6011) (image 65: 40 = pmp and pms_sram off, +1/+2 = still on; image 67: +10 = the SEP step ran, +4 = outbox still enabled, +8 = ps_sep not 0x10....0f; 50 = all as macOS; ff = step not run)"
echo "0x6001/2/3 boot stage $(b 6001), error count $(b 6002), error stage $(b 6003); 0x6010 loader flag $(b 6010); 0x6017 $(b 6017)"
if [ "${1:-}" = zero ]; then
    for r in 6004 6005 6006 6007 600c 600d 600e 6011 6012 6013 6014 6015 6016 601b 601c 601d 601e; do
        printf '\0' | dd of=$N bs=1 seek=$((0x$r)) count=1 conv=notrunc 2>/dev/null
    done
    echo "zeroed: $(dd if=$N bs=1 skip=$((0x6000)) count=32 2>/dev/null | xxd -p | tr -d '\n')"
fi
