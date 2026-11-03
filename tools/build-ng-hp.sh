#!/bin/zsh
# NootedGreen da variante HP Dragonfly G2 (TGL nativo no Tahoe): sgiammori/NootedGreen@95f8189 (que tem os headers
# de firmware GuC/HuC) com o src/NootedGreen publicado em yankedi/HP-Elite-Dragonfly-G2-Hackintosh/graphics por cima.
# Compila como o build-nootedgreen.sh do XPS (so Command Line Tools), reaproveitando as deps dele.
#   zsh build-ng-hp.sh <dir-sgiammori> <dir-hp-src> <dir-deps-do-xps> <saida/NootedGreen.kext>
set -e
UP=${1:?sgiammori}; HP=${2:?hp src}; DEPS=${3:?deps}; OUT=${4:?saida}
NAME=NootedGreen; BID=com.StezzaPilot.NootedGreen; VER=1.0.0
SRC=$(mktemp -d)/NootedGreen; TMP=$(mktemp -d)
cp -R $UP/NootedGreen $SRC; cp $HP/* $SRC/
SDK=$DEPS/MacKernelSDK; LILU=$DEPS/Lilu.kext/Contents/Resources
rm -rf $OUT; mkdir -p $OUT/Contents/MacOS
sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BID/g" -e "s/\$(PRODUCT_NAME:rfc1034identifier)/$NAME/g" \
    -e "s/\$(PRODUCT_NAME)/$NAME/g" -e "s/\$(EXECUTABLE_NAME)/$NAME/g" -e "s/\$(MODULE_VERSION)/$VER/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$VER/g" -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" -e "s/\$(MODULE_NAME)/$BID/g" \
    $SRC/Info.plist > $OUT/Contents/Info.plist
FLAGS=(-arch x86_64 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector
       -mmacosx-version-min=13.0 -mmmx -msse -msse2
       -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
       -DDEBUG=1 -DAPPLE_KEXT_ASSERTIONS=1 -DPRODUCT_NAME=$NAME -DMODULE_VERSION=$VER
       -isystem $SDK/Headers -I$LILU -O2 -g)
cat > $TMP/info.c <<EOC
#include <mach/mach_types.h>
extern kern_return_t ${NAME}_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t ${NAME}_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL($BID, "$VER", ${NAME}_kern_start, ${NAME}_kern_stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOC
clang $FLAGS -c $TMP/info.c -o $TMP/info.o
# mesma lista do build do HP (kern_netdbg.cpp fica fora tambem no projeto original: usa <cstdarg>)
for s in DisplayMergeNub DYLDPatches Firmware FirmwareADLP HDMI IntelDPLinkTraining kern_gen11 kern_genx kern_green kern_patcherplus kern_start; do
  f=$SRC/$s.cpp
  clang++ $FLAGS -std=gnu++17 -nostdinc++ -fno-exceptions -fno-rtti -fapple-kext \
    -Wno-deprecated-declarations -Wno-inconsistent-missing-override -Wno-unused-parameter -c $f -o $TMP/${f:t:r}.o
done
clang++ $FLAGS -std=gnu++17 -nostdinc++ -fno-exceptions -fno-rtti -fapple-kext -c $LILU/Library/plugin_start.cpp -o $TMP/plugin_start.o
clang++ -arch x86_64 -mkernel -nostdlib -static -Xlinker -kext -Xlinker -export_dynamic -mmacosx-version-min=13.0 \
  $TMP/*.o $SDK/Library/x86_64/libkmod.a -lcc_kext -o $OUT/Contents/MacOS/$NAME
codesign -f -s - $OUT >/dev/null 2>&1 || true
rm -rf $TMP ${SRC:h}
echo "built $OUT"
