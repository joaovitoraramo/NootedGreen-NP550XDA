#!/bin/bash
# Espera o próximo reset de GPU no notebook (ioreg xe-rec-resets) e imprime os rastros XE-HANGDIAG/BBTRACE do full-<boot>.txt.
T=$(cd "$(dirname "$0")" && pwd); N=${1:-40}; falhas=0
for i in $(seq 1 $N); do
  R=$($T/mac.sh 'r=$(ioreg -l 2>/dev/null | grep -oE "\"xe-rec-resets\" = [0-9]+" | grep -oE "[0-9]+$"); echo "r=${r:-0} u=$(who | wc -l | tr -d " ") up=$(uptime | sed -E "s/.*up ([^,]+),.*/\1/")"' 2>/dev/null)
  echo "[$(date +%H:%M:%S)] $R"; if [ -z "$R" ]; then ping -c 2 -W 2000 192.168.100.54 >/dev/null 2>&1 && echo "  (ping responde: rede viva, ssh nao)" || echo "  (ping morto: kernel/rede fora)"; falhas=$((falhas+1)); echo "SEM RESPOSTA ($falhas)"; [ $falhas -ge 2 ] && { echo "CONGELOU? ssh morto 2x seguidas"; break; }; else falhas=0; fi
  n=$(echo "$R" | sed -nE 's/^r=([0-9]+).*/\1/p')
  if [ -n "$n" ] && [ "$n" -gt 0 ]; then echo "RESET DETECTADO"; sleep 3
    $T/mac.sh 'F=$(ls -t /var/log/claude-boot/full-*.txt | head -1); grep -nE "XeNG HANGDIAG|XeNG SUBTRACE|XeNG BBTRACE|XeNG STAMPWAIT|XeNG GPUREC|XeNG STAMPFIX|IPEHR=0x" $F | grep -v "SUBTRACE:  #" | cut -c1-330 | head -90'; break; fi
  sleep 60
done; echo FIM-ESPERA
