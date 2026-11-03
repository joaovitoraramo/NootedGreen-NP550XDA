#!/usr/bin/env python3
# patch-va-no-videoprocessing.py <plugin binary>  (run after JulioNectar's build-vadriver.sh; re-sign ad-hoc afterwards)
# Workaround for RCS hangs on real TGL when a video plays in the App Store. AppleGVA chains a video-processing step after
# the decoder; ops 0x1 and 0x10 create AVD_VideoProcessingContext, whose media batches (MEDIA_VFE_STATE + MEDIA_OBJECT)
# hang the RCS. This empties the output list (+0x224) of the 19 type-2 capability nodes so AppleGVA no longer selects them.
# Effect measured on i7-1165G7: no media batches and no resets; HEVC and HEVC 10-bit stay in hardware; H.264 hardware
# sessions fail with -12913 (AppleGVA requires nodes 0x786da0 and 0x7871d0 for H.264) and players fall back to software.
# Keeping those two nodes brings the hangs and the green picture back. The cause of the hang itself is still unknown.
import sys, struct
NODES = [0x786da0, 0x7871d0, 0x787600, 0x787a30, 0x788290, 0x7886c0, 0x788af0, 0x789350, 0x789780, 0x789bb0, 0x789fe0,
         0x78a410, 0x788f20, 0x78cdf0, 0x78e710, 0x78eb40, 0x78ef70, 0x78f7d0, 0x78fc00]
p = sys.argv[1]; d = bytearray(open(p, 'rb').read())
for a in NODES:
    assert struct.unpack_from('<I', d, a)[0] == 2, f'node {a:#x} is not type 2: unexpected plugin build'
    struct.pack_into('<I', d, a + 0x224, 0)
open(p, 'wb').write(d); print(f'{len(NODES)} type-2 nodes emptied')
