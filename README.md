# NootedGreen for the Samsung NP550XDA (real Tiger Lake, macOS Tahoe 26.7.1)

Fork of [sgiammori/NootedGreen](https://github.com/sgiammori/NootedGreen) (base `95f8189`, via the HP Dragonfly G2 source
published by [yankedi](https://github.com/yankedi/HP-Elite-Dragonfly-G2-Hackintosh)) adapted to a **real Tiger Lake-U
laptop**: Samsung NP550XDA, i7-1165G7, Iris Xe 96 EU (8086:9a49), 24 GB, running **macOS Tahoe 26.7.1 (25G241)** with full
Metal acceleration. The kext source is in the root of this repository (one file per subsystem, same layout as upstream
`src/NootedGreen`); the diagnostic and test tools we wrote along the way are in `tools/`.

This is a working daily machine as of 2026-11-03: Xcode 26.1.1 + iOS simulator, Docker Desktop, App Store, hardware video
decode, 9 h 23 min of continuous logged-in use overnight with zero GPU resets. One problem remains open (the idle login-screen freeze, see below) and **we are looking for help on it**; the post-reset
slowdown was solved on 2026-11-03 (GT frequency floor).

## Hardware and software

| Item | Value |
| --- | --- |
| Laptop | Samsung NP550XDA (Samsung Notebook, 2021) |
| CPU / iGPU | i7-1165G7 (Tiger Lake-U), Iris Xe 96 EU, PCI 8086:9a49, DVMT as shipped |
| RAM / SSD | 24 GB, Kingston NV3 1 TB NVMe |
| Panel | 15.6" 1920x1080 60 Hz eDP |
| Network | Realtek RTL8111 (RealtekRTL8111), Intel AX201 Wi-Fi/BT (AirportItlwm 2.4.0, IntelBluetoothFirmware 2.5.1) |
| macOS | Tahoe 26.7.1 (25G241), SMBIOS MacBookPro16,x |
| OpenCore / Lilu / WhateverGreen | 1.0.x / 1.7.2 / 1.7.1 |
| Graphics stack | this NootedGreen + AppleIntelTGLGraphics 16.0.2 / AppleIntelTGLGraphicsFramebuffer in /Library/Extensions (from [JulioNectar's XPS 13 Plus Tahoe project](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe)), patched AppleIntelTGLGraphicsVADriver from the same project |

Boot arguments in daily use:

```
keepsyms=1 debug=0x100 -vi2c-force-polling msgbuf=1048576 -ngreenblr -ngreenfbdpmstgl ngreenblmax=17741
ngreencon3type=2048 -ngreenhdmiemu -ngreenhdmiout -ngreenhdmigammaoff -ngreentglwithgfx ngreenSched=3 ngreen-dmc=tgl
-ngreentgltahoe -ngreenfixbootmode amfi_get_out_of_my_way=1 -allow3d -disablegfxfirmware itlwm_he=1 -ngreengva
```

## What works

- Metal / 3D acceleration, WindowServer at 60 Hz, App Store, Xcode 26.1.1, iOS 26.1 simulator, Docker Desktop.
- Hardware video decode (H.264, HEVC, HEVC 10-bit) through the patched VA plugin (`-ngreengva`).
- Internal panel brightness (`-ngreenblr`, `ngreenblmax=`), display sleep with backlight only (`-ngreenfbdpmstgl`), BrightnessKeys.
- External displays: the native HDMI port (pipe B on the TC1 DDI, lit through the `HDMIEMU`/`HDMIOUT` path) works perfectly, and so does USB-C DisplayPort alt mode (1080p).
- Sleep is disabled by policy (`pmset sleep 0`); not investigated yet.

## Stability (as of 2026-11-03)

- Logged-in session: 9 h 23 min overnight, zero GPU resets, zero freezes; ~14 h accumulated without a single failure while
  a user session exists.
- GPU resets happen **only** while a video plays in the App Store (the media batches of the VA plugin hang the RCS,
  recovered by our GPUREC; see open problem 2). Plain hardware decode in a test app (`tools/gva/xe-vtcase.m`) never resets.
- The idle **login screen with no session** has died 3 times (13 min, 21 min and 112 min after boot): total freeze, no
  panic, no trace in the kernel log, last kernel line is the normal 1 Hz clock blit of SecurityAgent (open problem 1).

## Fixes found in this fork (chronological, see `git log`)

| Tag in commits | What it fixes |
| --- | --- |
| `NOAUX` | Accept the NP550XDA (subsystem 144d:c195) on 25G241. |
| `XE-BLR`, `-ngreenbldiag` | Backlight PWM control on the real TGL eDP. |
| `XE-FBDPMS` (`-ngreenfbdpmstgl`) | Display sleep by backlight only (full DPMS kills the panel on this machine). |
| `XE-FENCE` | Limit the boot framebuffer fence to 32 MB (cursor at 0x02040000 rendered as blocks). |
| `TGLCON`, `ngreencon<N>type/pipe/busid` | Dump and override the native connector table of real TGL. |
| `HDMIEMU`/`HDMIOUT` | Native HDMI port: emulated DP sink on DDI 3 so AGDC creates the framebuffer, then pipe B / TC1 DDI / Dekel PHY / HDMI PLL programmed by the kext (8 bpc 148.5 MHz, DBUF slice S2, RGB output). Working. |
| USB-C DP series (`USB-C DP:` commits) | Link training on DDI B following the i915 sequence: AUX power wells before training, DPCD 0x108 then 0x102, TRAINING_PATTERN_SET with lanes in one transaction, PHY combo B signal values from a Linux dump, N scalar, DCC clock select. Result: USB-C alt-mode 1080p works. |
| `AUX timeout` | Connector 3 has no AUX; answer timeout immediately (were 2240 x 6 ms on the login screen). |
| `XE-PWR` | RAPL PL1 via MCHBAR (BIOS leaves 10 W): 28 W on AC regulated by temperature, 15 W on battery. |
| `XE-GVAID`/`XE-GVAHEVC` (`-ngreengva`) | Hardware video through the XPS VA plugin on real TGL. |
| `XE-GPUREC` v1+v2 | RCS and CCS share the render reset domain (GDRST 0x2) but Apple restores only the engine that hung; the sibling is left with HWS_PGA=0, GFX_MODE=0, its context dropped and the scheduler waiting forever (the old "restart loop + WindowServer dies + watchdog panic"). We snapshot the sibling's reset-register list, restore it after a real GDRST and run `IGScheduler5::processGPUReset` for it. |
| `XE-STAMPFIX` | After a GPUREC reset, a stamp of the sibling engine is lost in the GDRST (submitted N, returned N-1 forever): complete it and signal waiters. 03/11: also complete orphan stamps whose owner process died (the Apple restart loop "no channel associated with stamp_idx" ran forever, freezing the session and stalling shutdown). |
| `V212` | `IGScheduler5::isGpuIdle` override from INSTDONE (real TGL never reports idle otherwise). |
| `xe/csbguard`, `xe/elsqwait`, `xe/nopage` (ported from the XPS project) | CSB event validation panic ("EL[0] was invalidated"), ELSQ write lost right after a context switch, `IGAccelResource::pageon` panic on DPI change. |
| **`xe/poolguard`** | **Root cause of the login-screen GPU hang** (two freezes, IPEHR=0xc01dbead): `resolve_ccs` in AppleIntelTGLGraphics asks `IOAccelCommandBufferPool2::getBufferPtrNoInc` for 2 dwords (`movl $2,%esi`) and then writes a 0x224-byte batch, so a batch starting in the last bytes of a 16 KB pool buffer overflows into the next page (GPU executes garbage, CPU corrupts kernel memory). The guard starts a new batch only when at least 4 KB are free in the current buffer. Login screen: 2 h+ clean after, previously ~10 min. |
| `xe/poolfree` | The diagnostic pool table kept a pointer to a freed pool (one sudden death at process exit). |

Diagnostics kept in the kext (all read-only unless noted): `sysctl debug.xeng.regs` (display/GT live registers),
`debug.xeng.ringregs` (RCS/BCS/CCS/GT-IRQ register blocks with forcewake), `debug.xeng.ringsample` (2 s histogram of
IPEHR/ACTHD/EXECLIST_STATUS), `debug.xeng.irqstat` (interrupt counters, per command streamer stamp mask and refcounts),
`debug.xeng.stamps` (64 stamps with last submitting process), `debug.xeng.evdump` (scheduler event timeline into the kernel
log), `debug.xeng.poke="reg val"` (write a register, experiments only), `debug.xeng.irqfix` (re-enable engine interrupt on
the bridge). Kernel log lines are prefixed `XeNG`. The notebook logs `dmesg` continuously to disk (`tools/claude-bootlog.sh`)
so a frozen machine still leaves a trace.

## Open problems (help wanted)

### 1. Silent total freeze at the idle login screen (no session)

Three occurrences, all with no user logged in, 13 / 21 / 112 minutes after boot. The machine stops answering ping (wired
Ethernet), the clock on the login screen stops, no panic text (`debug=0x100 keepsyms=1`), nothing in NVRAM, nothing in the
kernel log beyond the normal per-second SecurityAgent blit, no GPU reset before it, disk writing normally (APFS tx every
40 s), sleep/display sleep disabled, AC power. The same build never died with a session open (14 h). Hypotheses we are
testing: deepest idle state of the platform (no Docker VM, no user session), something in the login-screen render path.
A 1 kHz CPU wake-up keepalive test is prepared.

### 2. Persistent slowdown of the living WindowServer after GPU resets — SOLVED 2026-11-03

**Root cause: GT frequency.** Apple's `IGHardwareCommandStreamer5::setGTFrequencyMMIO` requests frequency 0 on every call
on this machine (the power object it asks depends on the GuC/SLPC, which is off with `-disablegfxfirmware`), so the GT
only ran fast because the hardware raised the clock on its own. The first GDRST reset that autonomous state and the GT
stayed at RPn (~100 MHz, `RPSTAT1 0x1381b4 = 0x603125`, RC6 counter frozen) until the WindowServer died, which happened
to idle the GT long enough to recover. Fix: the `XE-GTFREQ` floor from the XPS project now applies on real TGL too
(commit `7a8ae4a`): a request of 0 becomes `ngreengtfreq` MHz (default 1500, the hardware clamps to RP0). After 4 resets
in the App Store the WindowServer stays at 57.7 fps, GT at ~1.1 GHz, Metal completion latency 0.4 ms.
`-ngreennogtfreqtgl` restores the old behaviour. The notes below are kept as the record of what was ruled out.

Original description:

Playing a video in the App Store triggers RCS hangs every 10-16 s (VA plugin media batches: `PIPELINE_SELECT` media,
`MEDIA_VFE_STATE` with scoreboard, `MEDIA_INTERFACE_DESCRIPTOR_LOAD`, second-level `MI_BATCH_BUFFER_START` with
`MEDIA_OBJECT`; the gpuRestart report shows VFE/TSG0/CS and all EUs "not done", no page fault). GPUREC recovers every
time, but afterwards the **WindowServer that lived through the reset stays at ~21 fps (46 ms per frame)** until it is
killed; every Metal client sees ~30-45 ms completion latency while it presents. Facts established so far:

- `kill -9 WindowServer` + re-login cures it with the same kernel state; a new WindowServer degrades again only after new resets.
- During the degraded presentation the RCS sits ~95% of the time in `EXECLIST_STATUS 0x2098` with ACTHD not advancing,
  IPEHR = `PIPE_CONTROL` (0x7a000004) or `MI_SEMAPHORE_WAIT` poll (0x0e009002); the BCS is idle.
- Apple's reset report: `LastContextSwitchReason = ELEMENT_SWITCH | WAIT_ON_SEMAPHORE | WAIT_ON_SCANLINE`; a few stamps stay
  "BUSY" forever (orphans of the dead decoder process; the engine still has an "active context" for them).
- Not MMIO state: every GT/engine register that the reset changed (0x2050 RC_SLEEP_PSMI_CONTROL bit 12, 0x20b4 EMR, 0x7004,
  0xb104, 0xb138, 0xb170, 0xe424, 0xe434, 0xe48c ROW_CHICKEN4, ...) was restored live with `debug.xeng.poke`: no change.
- Not the stamp interrupt: completion interrupts keep arriving (counted at the bridge handler and the command streamer
  flush-notify handler), re-enabling the engine interrupt on `IGInterruptBridge` changes nothing.
- Display side identical (frame counter 61 Hz, PSR off, DC off, flip transactions by interrupt, no flip timeouts).

Next step on our side: complete the orphan stamps right after the reset (done 03/11, under test) and dump the scheduler
event timeline (`debug.xeng.evdump`) during a degraded frame. If you know the post-reset behaviour of
`IGScheduler5`/`IGHardwareCommandStreamer5` (contexts flagged by `IOAccelContext2::affectedByHardwareReset`), or why the
Xe-LP media pipeline hangs on these `MEDIA_OBJECT` batches from the VA plugin, please open an issue here.

## Building

```sh
# deps: Lilu.kext + MacKernelSDK as in upstream NootedGreen (we use the ones from the XPS project's build/deps)
zsh tools/build-ng-hp.sh <upstream NootedGreen tree with xcodeproj> <this repo> <deps dir> <out>/NootedGreen.kext
```

`tools/build-ng-hp.sh` copies these sources over the upstream tree's `src/NootedGreen` and runs xcodebuild. The daily
OpenCore config is generated by `tools/mk-efi.py` (device properties, kexts, boot-args; SMBIOS comes from a private
`smbios.json`).

## Credits

sgiammori and ChefKiss (NootedGreen), yankedi (HP Dragonfly G2 TGL source and the NOAUX/80EU lineage), JulioNectar
(XPS 13 Plus Tahoe project: TGL kexts for Tahoe, VA plugin fix, GPUREC/csbguard/elsqwait/nopage origins), fisherlin007
(real TGL reports on the upstream tracker). License: Thou Shalt Not Profit License 1.0, as upstream.
