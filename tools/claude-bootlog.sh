#!/bin/sh
# Grava o dmesg e o estado do WindowServer em disco continuamente (a cada 2 s), para sobrar um retrato se a maquina
# congelar (o msgbuf do kernel some no desligamento forcado). Primeiros 60 s: retratos a cada 5 s em arquivo proprio
# (o msgbuf de 128 KB gira e o inicio do boot se perde). Depois: dmesg-<boot>.txt (atual) + dmesg-<boot>-h<hora>.txt por hora.
# 02/11: full-<boot>.txt acumula sem perdas: a cada volta anexa so as linhas com carimbo de tempo maior que o ultimo
# visto (e as continuacoes sem carimbo logo depois delas), porque o msgbuf de 128 KB gira em poucos minutos.
D=/var/log/claude-boot; mkdir -p "$D"; B=$(date +%Y%m%d-%H%M%S)
# 03/11: log unificado (nivel info) dos processos da tela de login/energia, via pty para nao bufferizar (script -t 0).
(/usr/bin/script -q -t 0 "$D/ulog-$B.txt" /usr/bin/log stream --style compact --level info --predicate 'process IN {"loginwindow","SecurityAgent","powerd","bluetoothd","nfcd","apfsd","WindowServer","coreaudiod","runningboardd","kernel"}' >/dev/null 2>&1 &)
find "$D" -name "*.txt" -mtime +3 -delete 2>/dev/null
i=0; last=0
while :; do
  /sbin/dmesg > "$D/dmesg-$B.tmp" && /bin/mv "$D/dmesg-$B.tmp" "$D/dmesg-$B.txt"
  last=$(/usr/bin/awk -v last="$last" 'BEGIN{go=0; mx=last+0}
    { if (match($0, /^\[ *[0-9]+\.[0-9]+\]/)) { ts=substr($0, 2, RLENGTH-2)+0; go=(ts>last); if (go && ts>mx) mx=ts }
      if (go) print > "/dev/stderr" }
    END{ printf "%.6f", mx }' "$D/dmesg-$B.txt" 2>>"$D/full-$B.txt")
  [ $i -le 60 ] && [ $((i % 5)) -eq 0 ] && /bin/cp "$D/dmesg-$B.txt" "$D/dmesg-$B-t$(printf %03d $i).txt"
  [ $((i % 1800)) -eq 0 ] && /bin/cp "$D/dmesg-$B.txt" "$D/dmesg-$B-h$(date +%H%M).txt"
  { /bin/date +%T; /bin/ps -axo pid,stat,%cpu,etime,command | /usr/bin/grep -E "[W]indowServer|[l]oginwindow"; } >> "$D/ps-$B.txt"
  /bin/sync
  i=$((i+1)); [ $i -lt 300 ] && /bin/sleep 1 || /bin/sleep 2
done
