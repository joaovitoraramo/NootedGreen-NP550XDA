# External outputs on the NP550XDA: native HDMI and USB-C DP alt mode

Everything here is enabled by `-ngreenhdmiemu` (plus `-ngreenhdmiout` for the HDMI signal) and lives in `kern_gen11.cpp`.

**Read this first.** These are fixes for one laptop, not a general solution. Most register values come from a Linux (i915)
register dump of this machine with the same monitors lit. The HDMI path is hardcoded to 1080p60. On this board HDMI is
legacy TC1 (VBT HDMI-D, DDC pin 4 = GMBUS pin 9, no AUX) and USB-C is DDI B on the combo PHY through the PD mux. An
Alder Lake board will have different PHYs and different port mapping, so treat the method as reusable, not the numbers.

## Native HDMI (port AGDC 4, DDI 3, TC1, pipe B)

Problem: the framebuffer's AGDC path only knows DP. After the Insert on the port it keeps reading DPCD over AUX (timeouts)
and never asks for the EDID. The Apple framebuffer then only builds the plane and pipe B; transcoder, DDI and PHY stay off.

### Phase A: get AGDC to accept the port and read the EDID

| Apple function | What the kext does |
|---|---|
| `hwDoGMBusRequest` | Binary patch: pin check `cmp $8` to `cmp $16`, because the DDC is pin 9. |
| `getDDCBlock` | Own GMBUS read in the i915 order (`gmbus_xfer_read` with index, address 0x50), because Apple's sequence does not work on pin 9 and never writes the pin to GMBUS0. |
| Before each pin 9 transaction | TC-cold block through PCode (`TGL_PCODE_TCCOLD` 0x26), PHY ownership (DFLEXDPCSSS), PW3, and the TC1 AUX and DDI power wells (0x45444 and 0x45454, bits 7:6). Without AUX power GMBUS only gets NAK. |
| `readAUX` / `writeAUX` for DDI 3 | Synthetic DP 1.2 sink: reads come from a fake DPCD and writes are stored in it. |
| AGDC `doLinkTraining` for port 4 | Answers success and zeroes the status at `out+0x38`, because there is no DP link to train. |

The emulated sink answers: 0x000 = 0x12 (DP 1.2), 0x001 = 0x0A (HBR), 0x002 = 0x84 (4 lanes, enhanced framing),
0x003 = 0x01, 0x006 = 0x01 (8b/10b), 0x200 = 0x41 (sink count 1), 0x202/0x203 = 0x77 and 0x204 = 0x01 (always trained),
0x205 = 0x03, 0x600 = 0x01. Also `ngreencon3type=2048` so the connector is HDMI.

### Phase B: the kext lights the output itself

Trigger: when Apple writes the pipe B plane surface (0x7119C) after AGDC trained the port. Order follows i915
`hsw_crtc_enable` + `intel_ddi_pre_enable_hdmi`, in `hdmiEmuEnableOutput`:

1. Dekel PLL of TC1: `MG_PLL_ENABLE` 0x46030, power, then REFCLKIN, CORECLKCTL1, HSCLKCTL, PLL_DIV0/1, SSC, BIAS, TDC, enable and wait for lock.
2. DDI D clock from the TC PLL (0x4610C) and ungate the port clock (0x164280 bit 12).
3. TC1 IO power (0x45454) and FIA lanes (0x1638C0, 4 lanes).
4. PHY lanes: PCS_DW5, DP_MODE, TX_DPCNTL0/1/2 with the Linux HDMI values, and `TX_PMD_LANE_SUS` = 0. macOS leaves it at 0xc, lanes suspended, no signal at all.
5. DBUF: enable slice S2 (0x44FE8) and move pipe B's DDB into it. Apple places it over pipe A, which gives underrun bands on the panel.
6. Transcoder B: clock select 0x46144, 2200x1125 timings, `TRANS_DDI_FUNC_CTL_B` = 0xA0030000 (port D, HDMI, 8 bpc), enable.
7. MBUS/DBOX credits of pipe B (0x7103C), copied from pipe A if zero. Without them the plane gets no memory data.
8. RGB output: clear the CSC/YUV bits in PIPEMISC and output CSC (`-ngreenhdmigammaoff` keeps gamma in bypass).
9. `DDI_BUF_CTL_D` enable, then rewrite the plane surface to latch the new DDB.

Afterwards a register write hook (`hdmiOutKeep`) stops Apple's DP path from undoing what it does not recognise, and
`hwSetMode` takes the shortcut without LightUp.

Two traps worth knowing: 12 bpc as in the Linux dump (TMDS 222.75 MHz) made pipe B run at 90 Hz here, so 8 bpc at 148.5 MHz
keeps the same 8.91 GHz DCO and only changes HSDIV. And pin 9 needs its power wells before the first DDC read, not after.

## USB-C DP alt mode (port AGDC 2, DDI B, combo PHY)

Result: 1080p over HBR2 x2 through a USB-C hub. Apple follows the Ice Lake order, which does not work on Tiger Lake because
`DP_TP_CTL` lives in the transcoder.

| Step | What was wrong | Fix |
|---|---|---|
| Hotplug | `AppleIntelPort::linkTraining` gives up with "Port is not associated to any path". | AGDC `doLinkTraining` answers success; the real training happens later in `LightUpDP`. |
| Mode list | `getLinkConfig` derives lanes from `DDI_BUF_CTL` while the DDI is off: 1 lane, only 30 Hz modes. | Write width x2 into `DDI_BUF_CTL_B` with the DDI still off. Routing `getLinkConfig` hung the boot at the Apple logo, do not repeat that. |
| Modeset | `hwRegsNeedUpdate` says nothing changed with the transcoder off, so `hwSetMode` does a partial modeset and never reaches `LightUpDP`. | Answer "reprogram" for that framebuffer during that call. |
| Before training | Apple never programs DPLL1 and sets the transcoder too late. | On the `LINK_BW_SET` write: DPLL1 for the requested rate (DCO 8100 MHz, ref 19.2 MHz), PW2 and PW3, AUX A/B wells, then `TRANS_CLK_SEL_B` and `TRANS_DDI_FUNC_CTL_B` as i915 does. |
| AUX | Apple only requests the TC1 AUX well; AUX on DDI B times out. | Request the AUX A/B wells (0x45444) and keep them on while the port exists. |
| DPCD order | 0x100, 0x107 and 0x102 are written before the DDI is on; the hub stops answering AUX. | Hold those writes. On the first AUX transaction with the DDI on, send 0x107 = 00 01, then 0x100, then 0x102 = 21 00 00, as i915 does. |
| PHY values | Apple's combo PHY table (swing 6, N 0x7F, RTERM 0, cursor 0x18) leaves lane 0 without clock recovery. | Replace on write (0x6C600-0x6CBFF, `dpbPhyFix`) with the i915 values: TX_DW2 0xA098, TX_DW4 0x28003F, TX_DW5 0x20290030, N 0x47, TX_DW8 ODCC_CLK_SEL, PCS_DW1 without continuous DCC. Level 0 already uses level 1 values, because lane 0 only locks at level 1 and the hub drops HPD before Apple raises the swing. |
| Enhanced framing | Apple sets it in the DPCD but not in `DP_TP_CTL`. | Set bit 18 on `DP_TP_CTL_B` (0x61540). |
| DBUF | Same pipe B DDB overlap as HDMI. | Same move to slice S2. |

Method that worked for both: boot Linux with the output lit, dump the registers, and compare them with macOS field by field.
