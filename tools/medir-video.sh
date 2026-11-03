#!/bin/zsh
# Mede o notebook durante o vídeo da App Store sem abrir janela: flips/s do plano, CPU por processo, frequência da GT,
# resets e stamps do decodificador. Na primeira vez que o VTDecoderXPCService passa de 10% de CPU, tira uma amostra dele.
# Uso: medir-video.sh [voltas, cada uma ~4 s]
${0:A:h}/mac.sh "N=${1:-45}; A=0; for i in \$(seq 1 \$N); do
  f0=\$(sysctl -n debug.xeng.regs | grep -oE 'flipcount=[0-9a-f]+' | cut -d= -f2); /bin/sleep 1; f1=\$(sysctl -n debug.xeng.regs | grep -oE 'flipcount=[0-9a-f]+' | cut -d= -f2);
  fl=\$(( 0x\$f1 - 0x\$f0 ));
  t=\$(top -l 2 -n 6 -o cpu -s 1 -stats command,cpu | tail -6 | awk '{c=\$NF; \$NF=\"\"; printf \"%s=%s \", \$0, c}' | tr -s ' ');
  g=\$(sysctl -n debug.xeng.ringregs | tr ' ' '\n' | grep -E '^1381b4=' );
  r=\$(ioreg -l | grep -oE '\"xe-rec-resets\" = [0-9]+' | grep -oE '[0-9]+\$');
  v=\$(sysctl -n debug.xeng.stamps | tr ';' '\n' | grep -E 'VTDecoder' | sed -E 's/^ //' | tr '\n' ',' | cut -c1-120);
  as=\$(pgrep -x 'App Store' >/dev/null && echo aberta || echo fechada);
  echo \"[\$(date +%T)] appstore=\$as flips/s=\$fl resets=\${r:-0} gt \$g | \$t | \$v\";
  if [ \$as = aberta ] && [ \$((i % 4)) = 0 ]; then echo \"aneis: \$(sysctl -n debug.xeng.ringsample | cut -d';' -f1 | cut -c1-170)\"; fi;
  if [ \$A = 0 ] && [ \$as = aberta ]; then P=\$(pgrep -n VTDecoderXPCService); if [ -n \"\$P\" ]; then c=\$(ps -o %cpu= -p \$P | cut -d. -f1 | tr -d ' '); if [ \"\${c:-0}\" -ge 3 ]; then A=1; sudo sample \$P 2 -file /tmp/vt.sample >/dev/null 2>&1; sudo sample WindowServer 2 -file /tmp/ws.sample >/dev/null 2>&1; echo \"amostras tiradas (decodificador cpu \$c%)\"; fi; fi; fi;
done; echo FIM"
