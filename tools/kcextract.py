#!/usr/bin/env python3 -I
"""Extrai um kext de uma kernel collection (Mach-O fileset) para um Mach-O avulso que o otool consegue ler.
Uso: kcextract.py <kc> <entry_id substring> <saida>  |  kcextract.py <kc> list
(IOAcceleratorFamily2 e AppleIntelTGLGraphics estão em /System/Library/KernelCollections/SystemKernelExtensions.kc)"""
import struct, sys
LC_SEGMENT_64 = 0x19; LC_SYMTAB = 0x2; LC_DYSYMTAB = 0xb; LC_FILESET_ENTRY = 0x80000035
def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]
def lcs(b, base):
    ncmds, sizeofcmds = u32(b, base + 16), u32(b, base + 20)
    o = base + 32; out = []
    for _ in range(ncmds):
        cmd, size = u32(b, o), u32(b, o + 4); out.append((cmd, size, o)); o += size
    return out, sizeofcmds
def main():
    kc = open(sys.argv[1], "rb").read(); entries = []
    for cmd, size, o in lcs(kc, 0)[0]:
        if cmd == LC_FILESET_ENTRY:
            vmaddr, fileoff, stroff = u64(kc, o + 8), u64(kc, o + 16), u32(kc, o + 24)
            entries.append((kc[o + stroff:kc.index(b"\0", o + stroff)].decode(), vmaddr, fileoff))
    if sys.argv[2] == "list":
        for n, v, f in entries: print(f"{n} vmaddr=0x{v:x} fileoff=0x{f:x}")
        return
    name, vmaddr, base = next(e for e in entries if sys.argv[2] in e[0])
    print(f"entrada {name} vmaddr=0x{vmaddr:x} fileoff=0x{base:x}")
    cmds, sizeofcmds = lcs(kc, base); hdr = bytearray(kc[base:base + 32 + sizeofcmds]); out = bytearray(); segs = []
    for cmd, size, o in cmds:
        if cmd != LC_SEGMENT_64: continue
        segs.append((kc[o + 8:o + 24].rstrip(b"\0").decode(), o - base, u64(kc, o + 24), u64(kc, o + 32), u64(kc, o + 40), u64(kc, o + 48), u32(kc, o + 64)))
    for segname, lo, svm, svs, sfo, sfs, nsects in segs:
        if segname == "__LINKEDIT" or sfs == 0: newoff = 0
        else:
            while len(out) % 4096: out.append(0)
            newoff = len(out); out += kc[sfo:sfo + sfs]
        struct.pack_into("<Q", hdr, lo + 40, newoff); so = lo + 72
        for _ in range(nsects):
            saddr, soff = u64(hdr, so + 32), u32(hdr, so + 48)
            if soff: struct.pack_into("<I", hdr, so + 48, newoff + (saddr - svm))
            struct.pack_into("<I", hdr, so + 56, 0); struct.pack_into("<I", hdr, so + 60, 0); so += 80
        print(f"  {segname:14s} vm 0x{svm:x}+0x{svs:x} file 0x{sfo:x}+0x{sfs:x} -> 0x{newoff:x}")
    while len(out) % 4096: out.append(0)
    le = len(out)
    for cmd, size, o in cmds:
        lo = o - base
        if cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = u32(kc, o + 8), u32(kc, o + 12), u32(kc, o + 16), u32(kc, o + 20)
            nso = len(out); out += kc[symoff:symoff + nsyms * 16]; nst = len(out); out += kc[stroff:stroff + strsize]
            struct.pack_into("<IIII", hdr, lo + 8, nso, nsyms, nst, strsize); print(f"  symtab nsyms={nsyms}")
        elif cmd == LC_DYSYMTAB:
            for k in range(8, 80, 4): struct.pack_into("<I", hdr, lo + k, 0)
    while len(out) % 4096: out.append(0)
    for segname, lo, *_ in segs:
        if segname == "__LINKEDIT":
            struct.pack_into("<QQ", hdr, lo + 40, le, len(out) - le); struct.pack_into("<Q", hdr, lo + 32, len(out) - le)
    out[0:len(hdr)] = hdr; open(sys.argv[3], "wb").write(out); print(f"gravado {sys.argv[3]} ({len(out)} bytes)")
main()
