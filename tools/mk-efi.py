#!/usr/bin/python3 -I
"""Monta a EFI do OpenCore para o Samsung NP550XDA (i7-1165G7, Iris Xe 9A49) no macOS Tahoe 26.7.1 (25G241).

Base de quirks/NVRAM: config-install.plist do projeto XPS13Plus-IrisXe-Tahoe (testado no Tahoe 26.7.1).
SSDTs: projeto Samsung NT750XDA (mesma plataforma, DSDT SECCSD LH43STAR), conferidas contra o nosso DSDT.

Gera:
  efi/EFI/OC/config.plist        fase 1 (instalacao): sem NootedGreen, itlwm, trackpad em polling, verbose
  efi/EFI/OC/config-seguro.plist volta segura depois dos kexts TGL instalados (GPU como 9A78, sem aceleracao)
  efi/EFI/OC/config-acel.plist   fase 2 (aceleracao): NootedGreen + AirportItlwm; so usar depois de instalar
  efi/EFI/OC/config-final.plist  fase 3 (uso diario): fase 2 sem verbose/logs/polling do trackpad
                                 os drivers TGL em /Library/Extensions (ver INSTALL.md do projeto XPS)
Uso: /usr/bin/python3 -I mk-efi.py
"""
import copy, json, os, plistlib, shutil, subprocess, sys

H = '/Volumes/raid/Fontes/Pessoal/hackintosh-np550xda'
REL = f'{H}/releases'
XPS = f'{H}/repos/XPS13Plus-IrisXe-Tahoe'
NT750 = f'{H}/repos/Samsung-NT750XDA-TigerLake/EFI/OC/ACPI'
OCREL = f'{REL}/OpenCorePkg/OpenCore-1.0.8-RELEASE'
OUT = f'{H}/efi/EFI'
GUID = '7C436110-AB2A-4BBB-A880-FE41995C9F82'

# (destino em Kexts/, origem)
KEXTS = {
    'Lilu.kext':                  f'{REL}/Lilu/Lilu-1.7.2-RELEASE/Lilu.kext',
    # Primeiro boot do Tahoe instalado: panic "IPI timeout / TLB flush timeout" com a CPU 0 sem responder,
    # sintoma de TSC dessincronizado entre os nucleos. O NT750XDA (mesmo firmware Samsung) usa este kext.
    'CpuTscSync.kext':            f'{REL}/CpuTscSync/CpuTscSync-1.1.2-RELEASE/CpuTscSync.kext',
    'VirtualSMC.kext':            f'{REL}/VirtualSMC/VirtualSMC-1.3.8-RELEASE/Kexts/VirtualSMC.kext',
    'SMCProcessor.kext':          f'{REL}/VirtualSMC/VirtualSMC-1.3.8-RELEASE/Kexts/SMCProcessor.kext',
    'SMCBatteryManager.kext':     f'{REL}/VirtualSMC/VirtualSMC-1.3.8-RELEASE/Kexts/SMCBatteryManager.kext',
    'ECEnabler.kext':             f'{REL}/ECEnabler/ECEnabler-1.0.6-RELEASE/ECEnabler.kext',
    'WhateverGreen.kext':         f'{REL}/WhateverGreen/WhateverGreen-1.7.1-RELEASE/WhateverGreen.kext',
    # Fase 2: NootedGreen da variante HP Dragonfly G2 (sgiammori 95f8189 + patches para TGL nativo no Tahoe), compilado
    # no notebook por build-ng-hp.sh. O fork do XPS (Alder/Raptor Lake) congelava no 1o contexto Metal (31/10, 3x).
    'NootedGreen.kext':           f'{H}/trabalho/build/NootedGreen-hp.kext',
    'AppleALC.kext':              f'{REL}/AppleALC/AppleALC-1.9.8-RELEASE/AppleALC.kext',
    # Tahoe nao tem AppleHDA (saiu no 26 DP2): o SimpleHDA (laobamac) injeta o AppleHDA 600.2 do 15.8 via Lilu.
    'SimpleHDA.kext':             f'{REL}/SimpleHDA/x/SimpleHDA-Tahoe-v1.0.0-RELEASE/SimpleHDA.kext',
    'RestrictEvents.kext':        f'{REL}/RestrictEvents/RestrictEvents-1.1.6-RELEASE/RestrictEvents.kext',
    'NVMeFix.kext':               f'{REL}/NVMeFix/NVMeFix-1.1.3-RELEASE/NVMeFix.kext',
    'RealtekRTL8111.kext':        f'{REL}/RTL8111_driver_for_OS_X/RealtekRTL8111-V3.0.0/RealtekRTL8111-V3.0.0/Release/RealtekRTL8111.kext',
    'itlwm.kext':                 f'{REL}/itlwm/itlwm_v2.3.0_stable.kext/itlwm.kext',
    # CI do laobamac/itlwm 94f9007 (31/10); o do XPS (738d4c6, 18/10) fica em AirportItlwm-Tahoe-do-XPS.
    'AirportItlwm.kext':          f'{REL}/AirportItlwm-Tahoe-94f9007/AirportItlwm.kext',
    # Bluetooth como o XPS no Tahoe (IntelBluetoothFirmware/IntelBTPatcher 2.5.1, BlueToolFixup 2.7.3); os 2.4.0/2.7.2 ficam em releases.
    'IntelBluetoothFirmware.kext': f'{REL}/IntelBluetooth-2.5.1-do-XPS/IntelBluetoothFirmware.kext',
    'IntelBTPatcher.kext':        f'{REL}/IntelBluetooth-2.5.1-do-XPS/IntelBTPatcher.kext',
    'BlueToolFixup.kext':         f'{REL}/BlueToolFixup-2.7.3-do-XPS/BlueToolFixup.kext',
    # Mapa USB: sem ele o XHCI@14 do Tahoe sobe sem nenhuma porta (nem o Bluetooth interno). UTBMap gerado no
    # Windows com o USBToolBox (28/10): HS01+SS01 USB-A 3.x, HS02 USB-A 2.0, HS03 (7) e HS04 (10) internas.
    'USBToolBox.kext':            f'{REL}/USBToolBox-do-XPS/USBToolBox.kext',
    # trabalho/usb: o do Windows + USB-C (porta 3 do XHCI = USB 2 da USB-C; TXHC SS01-04 = portas 2-5, USB 3)
    # + leitor SD interno (Alcor 058f:6366 na porta 4, visto no Linux; so enumera com cartao).
    'UTBMap.kext':                f'{H}/trabalho/usb/UTBMap.kext',
    'VoodooPS2Controller.kext':   f'{REL}/VoodooPS2/VoodooPS2Controller-2.3.7-RELEASE/VoodooPS2Controller.kext',
    # O VoodooI2C 2.9.1 oficial nao casa o I2C (8086:a0e8) nem o GPIO (INT34C5) do Tiger Lake: o trackpad
    # nao funcionou no instalador. O do NT750XDA (2.8 com suporte a TGL) casa os dois; o VoodooInput dele
    # (1.1.4) e trocado pelo 1.1.6 do 2.9.1, o que o XPS usa no Tahoe.
    'VoodooI2C.kext':             f'{NT750}/../Kexts/VoodooI2C.kext',
    'VoodooI2CHID.kext':          f'{NT750}/../Kexts/VoodooI2CHID.kext',
    'BrightnessKeys.kext':        f'{REL}/BrightnessKeys/BrightnessKeys-1.0.3-RELEASE/BrightnessKeys.kext',
}

# Ordem de carga (Kernel > Add). (BundlePath, ExecutablePath, MinKernel, ativo na fase 1, ativo na fase 2)
ORDEM = [
    ('Lilu.kext', 'Contents/MacOS/Lilu', '', True, True),
    ('CpuTscSync.kext', 'Contents/MacOS/CpuTscSync', '', True, True),
    ('VirtualSMC.kext', 'Contents/MacOS/VirtualSMC', '', True, True),
    ('SMCProcessor.kext', 'Contents/MacOS/SMCProcessor', '', True, True),
    ('SMCBatteryManager.kext', 'Contents/MacOS/SMCBatteryManager', '', True, True),
    ('ECEnabler.kext', 'Contents/MacOS/ECEnabler', '', True, True),
    ('WhateverGreen.kext', 'Contents/MacOS/WhateverGreen', '', True, True),
    ('NootedGreen.kext', 'Contents/MacOS/NootedGreen', '25.0.0', False, True),
    ('AppleALC.kext', 'Contents/MacOS/AppleALC', '', True, True),
    ('SimpleHDA.kext', 'Contents/MacOS/SimpleHDA', '25.0.0', True, True),
    ('RestrictEvents.kext', 'Contents/MacOS/RestrictEvents', '', True, True),
    ('NVMeFix.kext', 'Contents/MacOS/NVMeFix', '18.0.0', True, True),
    ('RealtekRTL8111.kext', 'Contents/MacOS/RealtekRTL8111', '', True, True),
    ('USBToolBox.kext', 'Contents/MacOS/USBToolBox', '', True, True),
    ('UTBMap.kext', '', '', True, True),
    ('itlwm.kext', 'Contents/MacOS/itlwm', '', True, False),  # fase 2: fora enquanto depura (enche o msgbuf); AirportItlwm depois
    ('AirportItlwm.kext', 'Contents/MacOS/AirportItlwm', '25.0.0', False, True),  # fase 2: Wi-Fi nativo (AX201); nunca junto do itlwm
    ('IntelBluetoothFirmware.kext', 'Contents/MacOS/IntelBluetoothFirmware', '', False, True),  # fase 2: BT 8087:0AAA na HS04 (precisa do UTBMap)
    ('IntelBTPatcher.kext', 'Contents/MacOS/IntelBTPatcher', '', False, True),  # fase 2: BT 8087:0AAA na HS04 (precisa do UTBMap)
    ('BlueToolFixup.kext', 'Contents/MacOS/BlueToolFixup', '21.0.0', False, True),  # fase 2: BT 8087:0AAA na HS04 (precisa do UTBMap)
    ('VoodooPS2Controller.kext', 'Contents/MacOS/VoodooPS2Controller', '', True, True),
    ('VoodooPS2Controller.kext/Contents/PlugIns/VoodooPS2Keyboard.kext', 'Contents/MacOS/VoodooPS2Keyboard', '', True, True),
    ('VoodooI2C.kext/Contents/PlugIns/VoodooI2CServices.kext', 'Contents/MacOS/VoodooI2CServices', '', True, True),
    ('VoodooI2C.kext/Contents/PlugIns/VoodooGPIO.kext', 'Contents/MacOS/VoodooGPIO', '', True, True),
    ('VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext', 'Contents/MacOS/VoodooInput', '', True, True),
    ('VoodooI2C.kext', 'Contents/MacOS/VoodooI2C', '', True, True),
    ('VoodooI2CHID.kext', 'Contents/MacOS/VoodooI2CHID', '', True, True),
    ('BrightnessKeys.kext', 'Contents/MacOS/BrightnessKeys', '', True, True),
]

# SSDTs do NT750XDA. Fora de proposito: SSDT-NVME_OFF (no nosso RP09.PXSX e a Ethernet RTL8168),
# SSDT-HPET e SSDT-PMC (o XPS no Tahoe nao usa; testar NVRAM nativa primeiro).
SSDTS = ['SSDT-PLUG.aml', 'SSDT-EC-USBX.aml', 'SSDT-AWAC.aml', 'SSDT-OSYS.aml', 'SSDT-SPTP.aml',
         'SSDT-PNLF.aml', 'SSDT-ALS0.aml', 'SSDT-SBUS-MCHC.aml']
# Nossas (trabalho/ssdt). SSDT-BRTK: teclas Fn de brilho (EC _Q63/_Q64 -> PS2K), com os renomes de ACPI_PATCHES.
# SSDT-SKEY: teclas Fn de som (breakless e020/e02e/e030 no VoodooPS2).
SSDTS_NP550 = ['SSDT-BRTK.aml', 'SSDT-SKEY.aml']
ACPI_PATCHES = [('Fn brilho -: _Q63 -> XQ63 (SSDT-BRTK)', b'_Q63', b'XQ63'),
                ('Fn brilho +: _Q64 -> XQ64 (SSDT-BRTK)', b'_Q64', b'XQ64')]

BOOTARGS_F1 = '-v keepsyms=1 debug=0x100 -vi2c-force-polling'
# Fase 2: boot-args do XPS menos os especificos da Dell (ngreenblmax) e o XE-PM (ngreenpm, feito para CPU hibrida;
# fica para depois). DMC: o XPS (Alder Lake) carrega o firmware ADL-P; aqui o chip e Tiger Lake de verdade -> tgl.
# Agendador: o NootedGreen le a CPUID real (isRealTGL) e, em TGL de verdade, nao faz o pre-enable de IRQ (V54/V65)
# que o ngreenSched=4 do XPS precisa: com 4 o boot congelava no 1o contexto Metal do WindowServer (31/10, 2x).
# ngreenblmax=17741: a Apple nunca grava o periodo do PWM (o firmware deixa 96000) e no maximo pede duty 17741
# (18,5%); o XE-BLR reescala o duty por 96000/17741 (medido com -ngreenbldiag em 31/10).
# 3 e o padrao do NootedGreen para TGL real e o que levou um HP i5-1135G7 ao desktop (issue #19 do XPS).
# ngreenV142 so vale no caminho nao-TGL; saiu.
# -ngreengva (01/11): video por hardware (plugin VA do XPS em /Library/GPUBundles + XE-GVAID/GVAHEVC no TGL real). 02/11: trava o RCS
# nos lotes de midia do VTDecoderXPCService (PIPELINE_SELECT=1, MEDIA_OBJECT); Joao decidiu manter e corrigir a causa, nao desligar.
BOOTARGS_F2 = ('-v keepsyms=1 debug=0x100 ipc_control_port_options=0 -vi2c-force-polling msgbuf=1048576 -ngreenblr '
               '-ngreenfbdpmstgl ngreenblmax=17741 ngreencon3type=2048 -ngreenhpdtrace -ngreenhdmiemu -ngreenhdmiout -ngreenhdmigammaoff -ngreentglwithgfx ngreenSched=3 ngreen-dmc=tgl -ngreentgltahoe -ngreenfixbootmode IGLogLevel=3 '
               'amfi_get_out_of_my_way=1 -allow3d -disablegfxfirmware shda-lang=pt_BR itlwm_he=1 -ngreengva')
# Fase 3 (final, uso diario): a fase 2 sem o verbose, sem o trace de HPD e sem o IGLogLevel. keepsyms/debug=0x100
# ficam: so agem num panic. O polling do trackpad FICA: sem ele (VoodooI2C/VoodooGPIO por interrupcao, 01/11 01:10)
# vieram congelamentos totais (02:08 parado, 12:57 sob carga) e um boot parado depois do som; antes, horas sem nenhum.
BOOTARGS_F3 = BOOTARGS_F2.replace('-v ', '').replace('-ngreenhpdtrace ', '').replace('IGLogLevel=3 ', '')


def kext_entry(base, path, exe, mink, enabled):
    e = copy.deepcopy(base)
    e.update({'Arch': 'x86_64', 'BundlePath': path, 'Comment': '', 'Enabled': enabled,
              'ExecutablePath': exe, 'MaxKernel': '', 'MinKernel': mink,
              'PlistPath': 'Contents/Info.plist'})
    return e


def monta(fase):
    c = plistlib.load(open(f'{XPS}/EFI/OC/config-install.plist', 'rb'))
    smb = json.load(open(f'{H}/trabalho/smbios.json'))

    # ACPI
    c['ACPI']['Add'] = [{'Comment': s[:-4], 'Enabled': True, 'Path': s} for s in SSDTS + SSDTS_NP550]
    c['ACPI']['Patch'] = [{'Base': '', 'BaseSkip': 0, 'Comment': com, 'Count': 1, 'Enabled': True, 'Find': f,
                           'Limit': 0, 'Mask': b'', 'OemTableId': b'', 'Replace': r, 'ReplaceMask': b'', 'Skip': 0,
                           'TableLength': 0, 'TableSignature': b'DSDT'} for com, f, r in ACPI_PATCHES]
    c['ACPI']['Delete'] = []

    # DeviceProperties: GPU ja e 9A49 de fabrica; as props sao as do XPS (que spoofa para 9A49), mantidas
    # porque o NootedGreen as espera. Audio: ALC256 atras do Smart Sound (HDAS), como no NT750XDA (layout 38).
    gpu = c['DeviceProperties']['Add']['PciRoot(0x0)/Pci(0x2,0x0)']
    gpu['model'] = 'Intel Iris Xe Graphics'
    if fase in (2, 3):
        # Como o HP Dragonfly (mesmo chip 9A49 nativo, chega ao desktop): so o ig-platform-id. As props do XPS
        # (rps-control, force-online, complete-modeset...) ficam de fora.
        gpu = {'AAPL,ig-platform-id': gpu['AAPL,ig-platform-id'], 'model': 'Intel Iris Xe Graphics'}
    if fase == 'seguro':
        # Volta segura depois de instalar os kexts TGL em /Library/Extensions: eles casam 0x9a498086 (o ID real
        # deste chip) e, sem o NootedGreen, travam o boot. Apresentar a GPU como 9A78 (TGL GT1, que nenhum kext
        # do Tahoe nem os TGL casam) deixa o macOS no framebuffer do firmware, como na instalacao.
        gpu = {'device-id': bytes.fromhex('789a0000'), 'model': 'Intel Iris Xe Graphics (sem aceleracao)'}
    c['DeviceProperties']['Add'] = {
        'PciRoot(0x0)/Pci(0x2,0x0)': gpu,
        'PciRoot(0x0)/Pci(0x1F,0x3)': {'device-id': bytes.fromhex('c8340000'), 'layout-id': 38,
                                       'model': 'Realtek ALC256'},
    }

    # Kernel
    base = c['Kernel']['Add'][0]
    c['Kernel']['Add'] = [kext_entry(base, p, x, m, f2 if fase in (2, 3) else f1) for p, x, m, f1, f2 in ORDEM]
    c['Kernel']['Patch'] = []
    # CPUID: Tiger Lake-U real (806C1) apresentado como Ice Lake-U (706E5), como no NT750XDA.
    # O NootedGreen le a CPUID real por conta propria, entao isso nao muda o caminho dele.
    c['Kernel']['Emulate']['Cpuid1Data'] = bytes.fromhex('e5060700000000000000000000000000')
    c['Kernel']['Emulate']['Cpuid1Mask'] = bytes.fromhex('ffffffff000000000000000000000000')
    q = c['Kernel']['Quirks']
    q['ProvideCurrentCpuInfo'] = False   # so necessario em CPU hibrida (XPS); TGL e 4C/8T
    q['AppleXcpmExtraMsrs'] = True       # NT750XDA: sem isso para em EXITBS:START
    q['DisableIoMapper'] = True
    q['DisableRtcChecksum'] = True
    q['AppleXcpmCfgLock'] = True         # CFG Lock nao foi desbloqueado no BIOS

    # Misc
    c['Misc']['Boot']['Timeout'] = 3 if fase == 3 else 5
    # Final: sem seletor (o macOS sobe direto; Esc ou Option segurados ao ligar abrem o seletor, PollAppleHotKeys).
    # Para o Proxmox o usuario usa o F10 do BIOS.
    c['Misc']['Boot']['ShowPicker'] = fase != 3
    # So volumes APFS em discos SATA/NVMe/USB/PCI (Dortania, 0x10F0103): sem a ESP na lista. Com o seletor escondido o
    # OpenCore iniciava sozinho a entrada "NO NAME" (a propria ESP, cujo BOOTx64.efi e o OpenCore) quando o F10 do BIOS
    # mudava a ordem de boot -> "Failed to start OpenCore image - Already started", tela preta (01/11).
    c['Misc']['Security']['ScanPolicy'] = 0x10F0103
    # Logs nas configs de diagnostico, para ler pelo Proxmox quando o macOS nao sobe: o OpenCore grava opencore-*.txt
    # (com o log do boot.efi) na raiz da ESP, e o ApplePanic grava ali o panic do boot anterior (panic-*.txt).
    # Na final so o ApplePanic (o arquivo de log a cada boot e o console do OpenCore custam segundos).
    c['Misc']['Debug']['Target'] = 1 if fase == 3 else 67
    c['Misc']['Debug']['AppleDebug'] = fase != 3
    c['Misc']['Debug']['ApplePanic'] = True
    tools = []
    for t in ('OpenShell.efi', 'ControlMsrE2.efi', 'ResetSystem.efi'):
        tools.append({'Arguments': '', 'Auxiliary': True, 'Comment': t, 'Enabled': True, 'Flavour': 'Auto',
                      'FullNvramAccess': False, 'Name': t[:-4], 'Path': t, 'RealPath': False,
                      'TextMode': False})
    c['Misc']['Tools'] = tools

    # NVRAM
    c['NVRAM']['Add'][GUID]['boot-args'] = {2: BOOTARGS_F2, 3: BOOTARGS_F3}.get(fase, BOOTARGS_F1)
    c['NVRAM']['Add'][GUID]['prev-lang:kbd'] = b'pt-BR:128'
    # RestrictEvents: "Processador Desconhecido" em Sobre este Mac -> nome do CPU (revcpu/revcpuname ja estao em Delete).
    c['NVRAM']['Add']['4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102']['revcpu'] = 1
    c['NVRAM']['Add']['4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102']['revcpuname'] = 'Intel Core i7-1165G7'
    # O RestrictEvents so troca o nome com ProcessorType 0x0601 (1-6 nucleos); o XPS (14 nucleos) usa 0x0F01.
    c['PlatformInfo']['Generic']['ProcessorType'] = 0x0601

    # PlatformInfo
    g = c['PlatformInfo']['Generic']
    g['SystemProductName'] = smb['SystemProductName']
    g['SystemSerialNumber'] = smb['SystemSerialNumber']
    g['MLB'] = smb['MLB']
    g['SystemUUID'] = smb['SystemUUID']
    g['ROM'] = bytes.fromhex(smb['ROM'])

    # UEFI
    dbase = c['UEFI']['Drivers'][0]
    c['UEFI']['Drivers'] = [dict(copy.deepcopy(dbase), Arguments='', Comment=d, Enabled=True, Path=d)
                            for d in ('HfsPlus.efi', 'OpenRuntime.efi', 'ResetNvramEntry.efi', 'AudioDxe.efi')]
    # Som de boot do Mac (pedido 01/11): AudioDxe no HDA do PCH (1F.3, ALC256 codec 0) + OCEFIAudio_VoiceOver_Boot.mp3
    # do OcBinaryData em Resources/Audio. PlayChime Enabled toca sempre (nao olha o StartupMute da NVRAM, que aqui nao persiste).
    a = c['UEFI']['Audio']
    a.update({'AudioSupport': True, 'AudioDevice': 'PciRoot(0x0)/Pci(0x1F,0x3)', 'AudioCodec': 0, 'AudioOutMask': -1,
              'PlayChime': 'Enabled', 'MaximumGain': -15, 'MinimumAudibleGain': -55, 'MinimumAssistGain': -30,
              'SetupDelay': 0, 'DisconnectHda': False, 'ResetTrafficClass': False})
    c['UEFI']['Output']['Resolution'] = 'Max'
    return c


def main():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    shutil.copytree(f'{OCREL}/X64/EFI/BOOT', f'{OUT}/BOOT')
    os.makedirs(f'{OUT}/OC/ACPI'); os.makedirs(f'{OUT}/OC/Drivers'); os.makedirs(f'{OUT}/OC/Kexts')
    os.makedirs(f'{OUT}/OC/Tools'); os.makedirs(f'{OUT}/OC/Resources')
    shutil.copy2(f'{OCREL}/X64/EFI/OC/OpenCore.efi', f'{OUT}/OC/')
    for d in ('OpenRuntime.efi', 'ResetNvramEntry.efi', 'AudioDxe.efi'):
        shutil.copy2(f'{OCREL}/X64/EFI/OC/Drivers/{d}', f'{OUT}/OC/Drivers/')
    os.makedirs(f'{OUT}/OC/Resources/Audio')
    shutil.copy2(f'{REL}/OcBinaryData/Resources/Audio/OCEFIAudio_VoiceOver_Boot.mp3', f'{OUT}/OC/Resources/Audio/')
    shutil.copy2(f'{REL}/OcBinaryData/HfsPlus.efi', f'{OUT}/OC/Drivers/')
    for t in ('OpenShell.efi', 'ControlMsrE2.efi', 'ResetSystem.efi'):
        shutil.copy2(f'{OCREL}/X64/EFI/OC/Tools/{t}', f'{OUT}/OC/Tools/')
    for s in SSDTS:
        shutil.copy2(f'{NT750}/{s}', f'{OUT}/OC/ACPI/')
    for s in SSDTS_NP550:
        shutil.copy2(f'{H}/trabalho/ssdt/{s}', f'{OUT}/OC/ACPI/')
    for dest, src in KEXTS.items():
        if not os.path.isdir(src):
            sys.exit(f'falta {src}')
        shutil.copytree(src, f'{OUT}/OC/Kexts/{dest}', symlinks=True)
    vi = f'{OUT}/OC/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext'
    shutil.rmtree(vi)
    shutil.copytree(f'{REL}/VoodooI2C/VoodooI2C-2.9.1-RELEASE/VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext', vi)
    plistlib.dump(monta(1), open(f'{OUT}/OC/config.plist', 'wb'))
    plistlib.dump(monta(2), open(f'{OUT}/OC/config-acel.plist', 'wb'))
    plistlib.dump(monta('seguro'), open(f'{OUT}/OC/config-seguro.plist', 'wb'))
    plistlib.dump(monta(3), open(f'{OUT}/OC/config-final.plist', 'wb'))
    # Conferencia: cada kext referenciado existe com o executavel declarado
    for p, x, *_ in ORDEM:
        k = f'{OUT}/OC/Kexts/{p}'
        assert os.path.isfile(f'{k}/Contents/Info.plist'), p
        assert not x or os.path.isfile(f'{k}/{x}'), (p, x)
    v = f'{OCREL}/Utilities/ocvalidate/ocvalidate'
    for cfg in ('config.plist', 'config-acel.plist', 'config-seguro.plist', 'config-final.plist'):
        r = subprocess.run([v, f'{OUT}/OC/{cfg}'], capture_output=True, text=True)
        print(cfg, '->', (r.stdout + r.stderr).strip().splitlines()[-1], '| exit', r.returncode)


if __name__ == '__main__':
    main()
