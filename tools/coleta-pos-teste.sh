#!/bin/zsh
# Depois do teste da App Store: resets, stamps atrasados, drops, loop, NIVEL2 do plugin e fps de apresentação.
T=${0:A:h}; D=$T/../../dados-notebook/lentidao/pos-$(date +%H%M%S); mkdir -p $D
$T/mac.sh 'date +%H:%M:%S; uptime | sed "s/.*up/up/"; ioreg -l 2>/dev/null | grep -oE "\"xe-rec-(resets|stampfix)\" = [0-9]+" | tr "\n" " "; echo; pgrep -fl "VTDecoderXPCService|App Store$" | cut -c1-50; F=$(ls -t /var/log/claude-boot/full-*.txt | head -1)
echo "-- resets"; grep -E "XeNG GPUREC" $F | sed -E "s/^\[ *([0-9]+)\..*\(n=([0-9]+)\)/\1:n\2/" | tr "\n" " "; echo
echo "-- loop"; grep -c "no channel associated" $F
echo "-- stamps"; grep -E "XeNG STAMPS|XeNG DISPSTAMPFIX" $F | cut -c1-110 | tail -40
echo "-- stampfix"; grep -E "XeNG STAMPFIX" $F | cut -c1-130 | tail -8
echo "-- drops"; grep -E "XeNG DROPDIAG" $F | cut -c1-130 | tail -8; grep -c "commands on floor" $F
echo "-- expirou"; grep -E "initial wait for 1 second expired" $F | sed -E "s/^\[ *([0-9]+)\..*/\1/" | tr "\n" " "; echo
echo "-- registradores ao vivo"; a=$(sysctl -n debug.xeng.regs 2>&1); /bin/sleep 1; b=$(sysctl -n debug.xeng.regs 2>&1); fa=$(echo "$a" | grep -oE "frmcount=[0-9a-f]+" | cut -d= -f2); fb=$(echo "$b" | grep -oE "frmcount=[0-9a-f]+" | cut -d= -f2); echo "painel: $((0x${fb:-0} - 0x${fa:-0})) quadros/s"; echo "$b" | cut -c1-400
echo "-- registradores dos aneis (forcewake)"; sysctl -n debug.xeng.ringregs 2>&1 | tr " " "\n" | grep -E "^(224c|2224c|1a24c|20a8|220a8|2098|2234|20e4|190030|190034|190090|190098|1900a0)=" | tr "\n" " "; echo
echo "-- fps de apresentacao com amostra dos aneis"; cd ~/stress; (sudo launchctl asuser 501 sudo -u joaovitor -H /usr/bin/perl -e "alarm 40; exec @ARGV" ./xe-present 400 > /tmp/xp.txt 2>&1 &); /bin/sleep 1.5; echo "aneis durante: $(sysctl -n debug.xeng.ringsample 2>&1)"; /bin/sleep 9; grep -a quadros /tmp/xp.txt | cut -c1-110; echo "aneis em repouso: $(sysctl -n debug.xeng.ringsample 2>&1)"; echo "-- cliente longo"; tail -8 ~/stress/mtllong.log 2>/dev/null
sudo log show --last 8m --style compact --predicate "subsystem == \"xe.vadump\"" 2>/dev/null | grep -aE "ENVIO-MIDIA|NIVEL2|classe|c[0-9]+ \+|NOSCORE|  res" | sed -E "s/^[-0-9]+ [0-9:.]+ E +//; s/VTDecoderXPCService\[[0-9:a-f]+\] //; s/\[xe.vadump:va\] //" > /tmp/vd.txt; echo "-- vadump: $(wc -l < /tmp/vd.txt) linhas"; grep -aE "NIVEL2" /tmp/vd.txt | head -4 | cut -c1-120' 2>&1 | tee $D/resumo.txt
rsync -a -e "ssh -i $HOME/.ssh/np550-key -o IdentitiesOnly=yes" joaovitor@192.168.100.54:/tmp/vd.txt $D/vadump.txt 2>/dev/null
echo "salvo em $D"
