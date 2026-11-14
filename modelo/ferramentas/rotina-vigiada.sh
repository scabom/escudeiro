#!/bin/bash
# Rotina vigiada — embrulha uma rotina agendada (LaunchAgent) para ela NUNCA falhar em silêncio.
#
# Uso (no ProgramArguments do plist; veja mac/launchd/ no pacote):
#   /bin/bash <pasta do agente>/ferramentas/rotina-vigiada.sh <nome> [--avisar N] [--pausar M] -- <comando> [args...]
#
#   --avisar N  avisa no Telegram quando a rotina falhar N vezes SEGUIDAS (padrão 1)
#   --pausar M  depois de M falhas seguidas, PAUSA a rotina e avisa (padrão 10; 0 = nunca pausa)
#
# Falhar = o comando sair com código diferente de 0.
# Voltou a funcionar depois de um aviso? Avisa também, para o dono não ficar preocupado à toa.
# Pausada: o launchd continua chamando, mas o embrulho não roda o comando até alguém
# apagar a marca:  rm <pasta do agente>/logs/estado/<nome>.pausada
# O aviso nunca leva a saída do comando (pode ter dado pessoal). O histórico de ok/falha fica em
# <pasta do agente>/logs/rotinas/<nome>.log, que o vigia-atrasos.py lê.
export PATH="$HOME/.bun/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
. "$(dirname "$0")/comum.sh"

NOME="$1"; shift
[ -n "$NOME" ] || { echo "uso: $0 <nome> [--avisar N] [--pausar M] -- <comando>" >&2; exit 2; }
AVISAR=1; PAUSAR=10
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  case "$1" in
    --avisar) AVISAR="$2"; shift 2 ;;
    --pausar) PAUSAR="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$1" = "--" ] && shift

mkdir -p "$LOGS/rotinas"
CONTA="$ESTADO/$NOME.falhas"
PAUSA="$ESTADO/$NOME.pausada"
LOG="$LOGS/rotinas/$NOME.log"
agora() { date '+%Y-%m-%d %H:%M:%S'; }

avisar() {
  if ERRO=$(avisar_telegram "$1" 2>&1); then
    echo "$(agora) aviso entregue: $1" >> "$LOG"
  else
    echo "$(agora) AVISO NAO ENTREGUE: $ERRO" >> "$LOG"; return 1
  fi
}

if [ -f "$PAUSA" ]; then
  echo "$(agora) pausada, não rodei (apague $PAUSA para religar)" >> "$LOG"
  exit 0
fi

# "início" é o que o vigia-atrasos.py olha para saber se a rotina rodou na hora.
echo "$(agora) início" >> "$LOG"
# A saída do comando segue para o StandardOutPath do plist.
"$@"
CODIGO=$?

FALHAS=$(cat "$CONTA" 2>/dev/null | tr -dc '0-9'); FALHAS=${FALHAS:-0}

if [ "$CODIGO" -eq 0 ]; then
  echo "$(agora) ok" >> "$LOG"
  if [ "$FALHAS" -ge "$AVISAR" ]; then
    avisar "✅ Rotina \"$NOME\" voltou a funcionar, depois de $FALHAS falha(s) seguida(s). — $NOME_AGENTE"
  fi
  rm -f "$CONTA"
  exit 0
fi

FALHAS=$((FALHAS + 1))
echo "$FALHAS" > "$CONTA"
echo "$(agora) FALHOU (código $CODIGO), $FALHAS seguida(s)" >> "$LOG"

if [ "$PAUSAR" -gt 0 ] && [ "$FALHAS" -ge "$PAUSAR" ]; then
  touch "$PAUSA"
  avisar "⏸️ Pausei a rotina \"$NOME\": falhou $FALHAS vezes seguidas (último código $CODIGO). Ela fica parada até a gente olhar. — $NOME_AGENTE"
elif [ "$FALHAS" -eq "$AVISAR" ]; then
  avisar "⚠️ A rotina \"$NOME\" falhou ($FALHAS vez(es) seguida(s), código $CODIGO). Se continuar falhando, ela é pausada em $PAUSAR falhas. — $NOME_AGENTE"
fi
exit "$CODIGO"
