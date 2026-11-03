#!/bin/bash
# ssh no notebook NP550 (cabo .54). Chave em ~/.ssh/np550-key (recriada 02/11 depois do host reiniciar e perder /tmp).
exec ssh -i ~/.ssh/np550-key -o IdentitiesOnly=yes -o ConnectTimeout=8 -o BatchMode=yes joaovitor@${NP_IP:-192.168.100.54} "$@"
