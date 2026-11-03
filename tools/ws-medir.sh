#!/bin/zsh
# Amostra o WindowServer por 10 s (em 1 ms) e conta o que ele fez: mede fluidez sem depender da impressão visual.
# Uso: ws-medir.sh <nome>; rodar com alguém arrastando janela.
N=$1; T=${0:A:h}
$T/mac.sh "sudo sample WindowServer 10 1 -mayDie -file /tmp/ws-$N.txt >/dev/null 2>&1; F=/tmp/ws-$N.txt; ioreg -l 2>/dev/null | grep -oE '\"xe-rec-resets\" = [0-9]+'; for k in CGXUpdateDisplay 'WS::Updater::UpdateDisplays' 'render_update' 'CDSurface::finish' 'IOAccelCommandQueueSubmitCommandBuffers' 'IOAccelDisplayPipeTransactionBegin' 'CGXRunOneServicesPass  (SkyLight) + 797'; do printf '%-46s ' \"\$k\"; grep -F \"\$k\" \$F | sed -E 's/^[ +!:|]*//' | awk '{print \$1}' | sort -rn | head -1; done; awk '/Sort by top of stack/{p=1} /Binary Images/{p=0} p' \$F | cut -c1-74 | head -8; uptime | sed 's/.*load/load/'"
