#!/bin/bash
# Reads the PMU's legacy scratch keys (0x6000-0x601f) and decodes Aura's S2R crumbs (aura-ctl bit 0x4000, psci.c
# qs_crumb_snapshot). Run on main after a commit run that ended in a reset:  sudo bash tools/pmu-scratch.sh [zero]
# zero: clear Aura's keys afterwards (0x6004-0x6007, 0x600c-0x600e, 0x6011-0x6016, 0x601b-0x601f). 0x6010 is the
# one-shot loader's flag and 0x6017 is not ours: both are left alone.
N=$(ls /sys/bus/nvmem/devices/spmi_nvmem*/nvmem 2>/dev/null | head -1)
[ -r "$N" ] || { echo "no PMU nvmem (run with sudo)"; exit 1; }
B=($(dd if=$N bs=1 skip=$((0x6000)) count=32 2>/dev/null | xxd -p -c1))
echo "raw 0x6000-0x601f: ${B[*]}"
b() { echo "${B[$((0x$1 - 0x6000))]}"; }
case $(b 6004) in
    00) S="none (no crumb run, or zeroed)" ;; 11) S="entry" ;; 12) S="records taken" ;; 13) S="S2R timer written" ;;
    14) S="WD2 stopped" ;; 15) S="AIC masked" ;; 16) S="quiet commit: last access before the commit (expected for a commit run)" ;;
    1c) S="quiet commit: the late APSC step was entered and did not finish (image 71)" ;;
    1b) S="quiet commit with the late APSC step (image 70): last access before the commit" ;;
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
E=$((0x$(b 601f)))
if [ $((E & 0x80)) -ne 0 ]; then
    echo "0x601f EDPRCR release   $(b 601f) (image 72): boot core before: CORENPDRQ $((E & 1)) CWRR $((E >> 1 & 1)) COREPURQ $((E >> 2 & 1)), read-back not 0: $((E >> 3 & 1)); secondaries (ORed) before: CORENPDRQ $((E >> 4 & 1)) CWRR $((E >> 5 & 1)) COREPURQ $((E >> 6 & 1))"
else
    echo "0x601f EDPRCR release   $(b 601f) (image 72: bit 7 clear = the step did not run)"
fi
case "$(b 6004)" in a1|a2|a3|a4|af)
    echo "OBSERVER (image 74): stage $(b 6004) (a1 saw the commit, a2 sampled 3 s and wrote the words, a3 read every EDPRSR, af no commit seen)"
    echo "  3 s after the commit, as the observer reads them: ECPM $(b 6012) PCPM0 $(b 6013) PCPM1 $(b 601b) (>> 4; low nibble 0 = off, 10 = off and was gated, 1f = on)"
    P=$((0x$(b 600a))); echo "  observer's own EDPRSR $(b 600a) (calibration: bit 7 = read, PU $((P & 1)) must be 1)"
    echo "  cores that read powered (PU = 1), bit = Aura index: $(b 6009)$(b 6008); last index started $(b 600b) (ff = all read)"
    echo "  IMAGE 75 ONLY (replaces the two lines above and the CPU_OFF mask line):"
    echo "    before the commit, secondaries whose final WFI returned: $(b 6009)$(b 6008) (bit = Aura index; bit 15 = written), highest count $(b 600a), ISR OR $(b 600b) (80 IRQ, 40 FIQ)"
    echo "    3 s after, cores whose final WFI returned (boot core = bit 0): $(b 6006)$(b 6005), boot core count $(b 6007), ISR OR $(b 600c)"
    echo "  IMAGE 76 ONLY, stage a4 = the wake probe finished (at a3 the 0x6005-7 line above still holds the image 75 values):"
    echo "    after an IPI to each sleeping core: returned from WFI (state kept) $(b 6006)$(b 6005); restarted through the reset vector (had lost power) $(b 6009)$(b 6008)"
    echo "    (bit = Aura index, bit 15 = written); boot core WFI count $(b 6007); reset_dbg[0] $(b 600a); index being woken $(b 600b) (ff = done)"
    echo "  IMAGE 78 ONLY (replaces every observer line above; stage a4 = the diff was written):"
    echo "    PMGR power words that changed in the 3 s after the commit (CPU complex words left out): $((0x$(b 6005))) of about $((0x$(b 6006) * 2))"
    for e in "6007 6008 6009" "600a 600b 600c" "6012 6013 6014" "6015 6016 6017" "601b 601c 601d"; do
        set -- $e; o=$(b $1); f=$((0x$(b $2))); v=$((0x$(b $3)))
        echo "    ps-reg $((f & 7)) offset 0x$o (word at base + $((0x$o * 8))): actual $((f >> 4)) -> $((v >> 4)), target now $((v & 15))$([ $((f & 8)) -ne 0 ] && echo ', upper bits changed too')"
    done
    echo "  (image 73 used 0x6008 20 ms word, 0x6009 3 s word, 0x600a first-off x 16 ms, 0x600b boot core EDPRSR)" ;;
esac
echo "0x6001/2/3 boot stage $(b 6001), error count $(b 6002), error stage $(b 6003); 0x6010 loader flag $(b 6010); 0x6017 $(b 6017)"
if [ "${1:-}" = zero ]; then
    for r in 6004 6005 6006 6007 6008 6009 600a 600b 600c 600d 600e 6011 6012 6013 6014 6015 6016 601b 601c 601d 601e 601f; do
        printf '\0' | dd of=$N bs=1 seek=$((0x$r)) count=1 conv=notrunc 2>/dev/null
    done
    echo "zeroed: $(dd if=$N bs=1 skip=$((0x6000)) count=32 2>/dev/null | xxd -p | tr -d '\n')"
fi
