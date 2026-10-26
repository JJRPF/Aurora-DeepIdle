# Boot-time trace reference (run 5, macOS 14.8.9 under the Aura hypervisor)

Source: `console.txt` of run 5 (98 822 lines, 12:12:49 to 12:20:45, no per-line time stamps: positions are given as line number and
percent of the log). Tracers: SMC (`trace_smc.py`), PMP (`trace_pmp.py`). Guest: macOSTest, boot-args `hvsleep=1 apcie=0xfffffffe wdt=-1 clpc=0`.
This is the data the wake work (Phase 4 in `docs/s2r-plan.md`) starts from.

## What macOS does through the PMP (the power manager coprocessor)
`DEV_STATUS_TGT_WR` is the "device power target" register: one bit per domain. 657 writes in the run.

| Phase | Lines | What the target register does |
|---|---|---|
| Boot ramp-up | 193 to 38265 | targets are raised step by step from 0x8000, 0xc000, 0xe000, ... as drivers attach |
| Steady (login window) | up to 85908 | `PCPM0 PCPM1 DISP0_FE GFX` stay on; `AVD_SYS` (video decode) is on and `MSR0` (media scaler) toggles on and off about 580 times (0x22700 / 0x62700), about once a second |
| Media off | 89278 (90.3 %) | `0x2700`: AVD_SYS, MSR0 and their voltage requests off |
| **Display off** | **97502 (98.7 %)** | **`0x700`: DISP0_FE off. Only PCPM0, PCPM1, GFX left on** |
| Blip | 97825, 97884 | back to 0x2700 (DISP0_FE on) and 0x700 again |
| Last PMP write | 98024 | mailbox doorbell, sequence number 0x472 at `0x28e3d12c0` |
| Silence | about 98822 | about 800 lines of SMC and PMP reads, then the console stops; the Aura USB proxy no longer answers |

The display going off about 6 s before the end, then the whole SoC going quiet, is the signature of macOS starting to sleep (the guest's
`hvsleep` job runs `pmset sleepnow` 5 min after boot; this is 7 min 56 s in). It is still an inference: the guest's own sleep log was not read.

## PMP mailbox
`PMP started` at line 20985 (syslog endpoint: Init ENTRYSIZE=0x60 COUNT=0x20 and ENTRYSIZE=0x50 COUNT=0x10, GetBuf DVA 0x2a3e6c000).
Requests go through the registers at `0x28e3d12a0` (message), `0x28e3d12c8` (always 0 before the doorbell) and `0x28e3d12c0` (doorbell with a
running sequence number: 0x46b to 0x472 in the last 6000 lines); `0x28e3d1618 = 3` is written about 30 times in the last 6000 lines.

## SMC
329 distinct keys read, 16 written. Reads by count (top 15): MSXA 1153, MSX9 1152, mTPL 332, xPDs 306, MSxs 280, CLKM 154, B0CM 20, PDTR 19, PSTR 19, CHNC 19, BRSC 15, BMDA 14, BLCR 14, B0AV 12, B0AC 12.
Written keys (count): NTAP 1, UB0C 1, gP16 2, gP0d 1, gP17 1, gP02 1, gP19 2, D2JR 1, CH0B 1, CH0K 1, D4Au 2, MSX0 1152, MSX2 1152, gp03 18, MSxb 280, SAQz 1.
The SMC sleep keys (`slpw`, `slpa`, `WKTP` writes) never appear: if macOS sleep starts, it does not start there.

## Distinct SMC keys read (first-seen order)
```
RGEN B0FV BNCB UPOF UBNC MBSW MESS MSLD CLKM BRSC B0RS PDTR PSTR BMDA BMDT BAAC BACC B0SS B0CI BISS B0CM B0HM BR0C B0FG BR00 BR01 BR02 BR03 BR04 BR05 BR06 BR07 BR08 BR09 BR10 BR11 BR12 BR13 BR14 B0S1 BMSC BNSC B0QD B0CH B0SR B0IF B0IS BQCC B0QS BAST B0MS B0MT B0FI BFC1 BFC2 BFWC B0TC BDAQ BDFU BQX1 BMW1 BQD1 BDD1 BC1V B0R1 BR1W BQX2 BMW2 BQD2 BDD2 BC2V B0R2 BR2W BQX3 BQD3 BDD3 BC3V B0R3 BR3W CHPS CHA1 BL0A BL0B BLCC BLCR BLIC BLID BLPM BLPX BLTA BLTM BLTO BLTS BLTX BLTP B0AV B0AC B0IV BMSN BCF0 CHCC CHCE CHCR CHSC B0RM B0FC B0NC B0CA CH0V BSFC CHNC CHAS B0BL B0AT TG0V B0CT B0TE B0PS B0CU B0TF B0RC BMDN CHBI CHBV BVVL CHSL CH0D CHTC CH0R D1VR D1IR D1FC CHI1 D1DE D1PT D1BD D1is D1if D1ih D1ii D1im D1in D1PM D1PI D2VR D3VR D4VR D4IR D4FC D4DE D4PT D4is D4if D4ih D4ii D4im D4in D4PM D4PI AP1A AP2A AP3A AP4A ANWP ATP0 ATC0 D1IQ D1LI D1LG ATP1 ATC1 D2IQ D2LI D2LG ATP2 ATC2 D3IQ D3LI D3LG ATP3 ATC3 D4IQ D4LI D4LG zSPp U1S0 U1B0 D1Pd D1Vd D1Dp D1Ep D1PR D1pr D1CX D1CY D1CZ U2B0 D2Pd D2Vd D2Dp D2Ep D2PR D2pr D2CX D2CY D2CZ U3B0 D3Pd D3Vd D3Dp D3Ep D3PR D3pr D3CX D3CY D3CZ U4B0 D4Pd D4Vd D4Dp D4Ep D4PR D4pr D4CX D4CY D4CZ B0UC B0DC mTPL WKTP bHLD xPDs F0Ac TB0T BIMX DICT RPlt MSXA MSXn MSXN MSX9 MSXH MSXL Ts0P TH0x F1Ac TB2T F1Tg TB1T F0Tg PSVC TVA0 PSVR PPMC fdBA SDMX cePz fspz PU2C PU2R voFi TH0a mlPw xDPE cmFv PDBR TVS0 TSXR TH0b Ib8f voPi PMVC Ts1P TVS1 voF0 TPMP TVS2 voP0 PPSC Tp02 SDTo SBAL mlU0 TSVR TDVx TVV0 w001 cmF0 iaD4 SDTp xPPT mlU1 fph0 TCDX cmF1 TH1a TCHP cmF2 TW0P Tp00 PHPC TD12 TH1b xUPT FBAD SBAn mlUR PU1C PU1R TPSP cmFa TVm0 TMVR TSWR TCMb TS0P nn00 MSxs TRDX TPDX SAQd SAQ2 SAQ3 SAQa SAQ4 SAQb SAQc SAQ1 SAQx
```

## macOS system-sleep entry (guest sleep job, runs 7-11, 2026-10-25)

Captured from the guest's `pmset sleepnow`-style sleep (timestamps from run 11, Pi `hv/20261025-210635-eleventh`). Order on the wire:

1. SMC key writes `MSxb` (many, 2-byte values 0x0201..0x035d, from all CPUs): housekeeping before sleep.
2. SMC key **`MBSE` = `slpw`** (bytes `73 6c 70 77`, logged as 0x77706c73): the sleep warning / prepare step.
3. PMP `DEV_STATUS_TGT_WR` handshake, which is display power (decoded from run 11): starting from PCPM0+PCPM1+GFX (0x700), macOS adds DISP0_FE (0x2700), DISPEXT0_FE + DP0/DP1-SOC-VMAX (0x6700), DISPEXT1_FE + DP2/DP3-SOC-VMAX (0xe700), then drops them again in reverse: GFX off (0xe300), DISP0_FE off (0xc300), DISPEXT1_FE + DP2/DP3 off (0x4300), DISPEXT0_FE + DP0/DP1 off (0x300). Each write is answered in `DEV_STATUS_ACT` before the next. End state: only PCPM0 and PCPM1 (the CPU complexes) are requested, everything else is off.
4. SMC key **`MBSE` = `slpa`** (`73 6c 70 61`, 0x61706c73): the actual sleep trigger (the key the project rule forbids sending by hand).
5. Immediately: `SetAPPower` STATE=0x201 to the SMC management endpoint and to the PMP (both ack), then PMP `SetIOPPower` 0x201.
6. CPU start/stop register writes (`CPUSTART` 28e0a8000, one bit per core 1-6, 8-10), then PMP `TGT_WR` writes clearing PCPM1 (0x200) and PCPM0 (0x100) i.e. the CPU complexes, then a PMGR 0x2902801c0 write (the USB0 AON hook).
7. Every core writes `ACC_OVRD_EL1` (the HV skips it) and `CYC_OVRD` 0x3000001 (WFI_MODE=3, deep sleep) and idles; the SMC/PMP power the cores down.

Under the HV this is where it ends: the next rendezvous finds cores that are gone (`Failed to rendezvous, missing CPUs`) and the HV panic reboots the Mac. Masking CYC_OVRD WFI_MODE (run 9) and dropping the PCPM clears (run 11) do not help: step 5's `SetAPPower` is what powers the cores down. Steps 2 and 4 are the SMC calls Linux needs to reproduce; the wake path (what restarts the AP, which RVBAR) is not visible under the HV.
