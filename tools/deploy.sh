#!/bin/bash
# Compila o NootedGreen (fork ng-np550) no notebook, empacota a EFI no hack e grava o kext na EFI do notebook.
set -e
T=$(cd "$(dirname "$0")" && pwd); H=$T/../..
SSH="ssh -i $HOME/.ssh/np550-key -o IdentitiesOnly=yes"
cd $H/trabalho/ng-np550
rsync -a -e "$SSH" --exclude .git ./ joaovitor@192.168.100.54:ng-hp/np550-src/
$T/mac.sh 'cd ~/ng-hp && rm -rf out3 && zsh build-ng-hp.sh ~/XPS13Plus-IrisXe-Tahoe/build/deps/NootedGreen np550-src ~/XPS13Plus-IrisXe-Tahoe/build/deps out3/NootedGreen.kext > /tmp/build.log 2>&1; rc=$?; echo "build rc=$rc avisos=$(grep -c "warning:" /tmp/build.log)"; grep -E " error" -A4 /tmp/build.log | head -30; exit $rc'
cd $H/trabalho
rsync -a --delete -e "$SSH" joaovitor@192.168.100.54:ng-hp/out3/NootedGreen.kext/ build/NootedGreen-hp.kext/
n=$(/usr/bin/python3 mk-efi.py 2>&1 | grep -c "No issues"); echo "mk-efi: $n x No issues"; [ "$n" = 4 ]
D=$T/deploy; rm -rf $D && mkdir -p $D && cp -R $H/efi/EFI/OC/Kexts/NootedGreen.kext $D/
a=$(shasum -a 256 $D/NootedGreen.kext/Contents/MacOS/NootedGreen | cut -c1-16)
rsync -a --delete -e "$SSH" $D/NootedGreen.kext/ joaovitor@192.168.100.54:ng-hp/deploy/NootedGreen.kext/
b=$($T/mac.sh 'sudo diskutil mount disk0s2 >/dev/null && sudo rm -rf "/Volumes/NO NAME/EFI/OC/Kexts/NootedGreen.kext" && sudo cp -R ~/ng-hp/deploy/NootedGreen.kext "/Volumes/NO NAME/EFI/OC/Kexts/" && shasum -a 256 "/Volumes/NO NAME/EFI/OC/Kexts/NootedGreen.kext/Contents/MacOS/NootedGreen" | cut -c1-16; sudo diskutil unmount disk0s2 >/dev/null')
echo "sha hack=$a efi=$b"; [ "$a" = "$b" ] && echo DEPLOY-OK
