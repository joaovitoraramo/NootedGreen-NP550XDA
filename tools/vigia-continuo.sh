#!/bin/bash
# Vigia sem parar no primeiro reset: uma linha por novo reset, marcos de uptime, e encerra (com aviso) se o notebook morrer.
T=$(cd "$(dirname "$0")" && pwd); N=${1:-300}; falhas=0; ult=-1
for i in $(seq 1 $N); do
  R=$($T/mac.sh 'r=$(ioreg -l 2>/dev/null | grep -oE "\"xe-rec-resets\" = [0-9]+" | grep -oE "[0-9]+$"); echo "r=${r:-0} u=$(who | wc -l | tr -d " ") up=$(uptime | sed -E "s/.*up ([^,]+),.*/\1/")"' 2>/dev/null | tail -1)
  echo "[$(date +%H:%M:%S)] $R"
  if [ -z "$R" ]; then ping -c 2 -W 2000 192.168.100.54 >/dev/null 2>&1 && echo "  (ping responde: rede viva, ssh nao)" || echo "  (ping morto: kernel/rede fora)"; falhas=$((falhas+1)); [ $falhas -ge 3 ] && { echo "NOTEBOOK-SEM-RESPOSTA"; exit 1; }; else falhas=0; fi
  n=$(echo "$R" | sed -nE 's/^r=([0-9]+).*/\1/p')
  if [ -n "$n" ]; then
    if [ "$ult" -ge 0 ] && [ "$n" -gt "$ult" ]; then echo "NOVO-RESET total=$n"; $T/mac.sh 'F=$(ls -t /var/log/claude-boot/full-*.txt | head -1); grep -E "XeNG HANGDIAG: antes" $F | tail -1 | cut -c1-200; grep -E "XeNG GPUREC" $F | tail -1 | cut -c1-140'; fi
    [ "$n" -lt "$ult" ] && echo "NOTEBOOK-REINICIOU"
    ult=$n
  fi
  sleep 60
done; echo FIM-ESPERA
