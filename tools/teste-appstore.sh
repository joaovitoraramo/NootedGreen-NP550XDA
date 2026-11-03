#!/bin/zsh
# Espera o 1º reset de GPU (App Store aberta pelo João), fecha a App Store 35 s depois e roda a coleta.
T=${0:A:h}
r0=$($T/mac.sh 'ioreg -l 2>/dev/null | grep -oE "\"xe-rec-resets\" = [0-9]+" | grep -oE "[0-9]+$"' 2>/dev/null); r0=${r0:-0}; echo "[$(date +%H:%M:%S)] resets antes do teste: $r0"
for i in $(seq 1 600); do r=$($T/mac.sh 'ioreg -l 2>/dev/null | grep -oE "\"xe-rec-resets\" = [0-9]+" | grep -oE "[0-9]+$"' 2>/dev/null); [ -n "$r" ] && [ "$r" -gt "$r0" ] && { echo "[$(date +%H:%M:%S)] primeiro reset novo visto (r=$r)"; break; }; /bin/sleep 1; done
/bin/sleep 35
$T/mac.sh 'pkill -x "App Store"; /bin/sleep 3; pgrep -x "App Store" >/dev/null && pkill -9 -x "App Store"; echo "[$(date +%H:%M:%S)] App Store fechada"'
/bin/sleep 15
$T/coleta-pos-teste.sh
echo FIM-TESTE-APPSTORE
