#!/bin/zsh
# Salva os registradores dos anéis (sysctl debug.xeng.ringregs, com forcewake) em dados-notebook/ringregs/<rotulo>.txt,
# um "reg=val" por linha, e compara com outro rótulo se dado: ringregs.sh <rotulo> [rotulo-anterior]
T=${0:A:h}; D=$T/../../dados-notebook/ringregs; mkdir -p $D
$T/mac.sh 'sysctl -n debug.xeng.ringregs' | tr ' ' '\n' | grep = | sort > $D/$1.txt
echo "$1: $(wc -l < $D/$1.txt) registradores nao nulos"
[ -n "$2" ] && { echo "-- diferencas $2 -> $1 (reg: antes depois)"; join -t= -a1 -a2 -e VAZIO -o 0,1.2,2.2 $D/$2.txt $D/$1.txt | awk -F= '$2!=$3' ; }
exit 0
