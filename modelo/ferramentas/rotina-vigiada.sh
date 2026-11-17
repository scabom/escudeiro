#!/bin/bash
# Rotina vigiada — embrulha uma rotina agendada (LaunchAgent) para ela NUNCA falhar em silêncio.
#
# Uso (no ProgramArguments do plist; veja mac/launchd/ no pacote):
#   /bin/bash <cópia instalada>/ferramentas/rotina-vigiada.sh <nome> [--avisar N] [--pausar M] -- <comando> [args...]
#
#   --avisar N  avisa no Telegram quando a rotina falhar N vezes SEGUIDAS (padrão 1)
#   --pausar M  depois de M falhas seguidas, PAUSA a rotina e avisa (padrão 10; 0 = nunca pausa)
#
# Falhar = o comando sair com código diferente de 0. Por isso as rotinas embrulhadas
# devolvem código diferente de 0 também quando o trabalho rodou mas deu problema
# (backup com falha, conferência que não bateu, bom-dia que não foi entregue).
# O aviso de falha só conta como dado quando o Telegram aceitou: se não chegou, a
# próxima falha tenta avisar de novo.
# Voltou a funcionar depois de um aviso? Avisa também, para o dono não ficar preocupado à toa.
# Pausada: o launchd continua chamando, mas o embrulho não roda o comando até alguém
# apagar a marca:  rm <logs>/estado/<nome>.pausada
# O aviso nunca leva a saída do comando (pode ter dado pessoal). O histórico de ok/falha fica em
# <logs>/rotinas/<nome>.log, que o vigia-atrasos.py lê.
# <logs> = ~/Library/Logs/Escudeiro/<rótulo> nas rotinas instaladas (ESCUDEIRO_LOGS), ou
# <pasta do agente>/logs quando roda à mão.
export PATH="$HOME/.bun/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
. "$(dirname "$0")/comum.sh"

NOME="${1:-}"; shift
[ -n "$NOME" ] || { echo "uso: $0 <nome> [--avisar N] [--pausar M] -- <comando>" >&2; exit 2; }
AVISAR=1; PAUSAR=10
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  case "$1" in
    --avisar) AVISAR="$2"; shift 2 ;;
    --pausar) PAUSAR="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "${1:-}" = "--" ] && shift
case "$AVISAR" in ''|*[!0-9]*|0) AVISAR=1 ;; esac
case "$PAUSAR" in ''|*[!0-9]*) PAUSAR=10 ;; esac
case "$NOME" in *[!A-Za-z0-9._-]*|.*) echo "nome de rotina inválido: $NOME" >&2; exit 2 ;; esac
[ $# -gt 0 ] || { echo "faltou o comando depois de --" >&2; exit 2; }

mkdir -p "$LOGS/rotinas"
CONTA="$ESTADO/$NOME.falhas"
PAUSA="$ESTADO/$NOME.pausada"
AVISADO="$ESTADO/$NOME.avisada"   # existe = o aviso de falha CHEGOU ao dono
# "Pausada" e "o aviso da pausa chegou" são coisas diferentes: a pausa vale na hora; o
# aviso, enquanto não chegar, é tentado de novo a cada chamada (sem rodar a rotina).
PAUSA_AVISADA="$ESTADO/$NOME.pausa-avisada"
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
  if [ ! -f "$PAUSA_AVISADA" ]; then
    FALHAS=$(cat "$CONTA" 2>/dev/null | tr -dc '0-9')
    avisar "⏸️ A rotina \"$NOME\" está PAUSADA depois de ${FALHAS:-várias} falhas seguidas. Ela fica parada até a gente olhar. — $NOME_AGENTE" \
      && touch "$PAUSA_AVISADA" "$AVISADO"
  fi
  exit 0
fi
# Religada (alguém apagou a marca de pausa): a marca do aviso da pausa perdeu o sentido.
rm -f "$PAUSA_AVISADA"

# "início" é o que o vigia-atrasos.py olha para saber se a rotina rodou na hora.
echo "$(agora) início" >> "$LOG"
# A saída do comando segue para o StandardOutPath do plist.
"$@"
CODIGO=$?

FALHAS=$(cat "$CONTA" 2>/dev/null | tr -dc '0-9'); FALHAS=${FALHAS:-0}

if [ "$CODIGO" -eq 0 ]; then
  echo "$(agora) ok" >> "$LOG"
  if [ -f "$AVISADO" ]; then
    avisar "✅ Rotina \"$NOME\" voltou a funcionar, depois de $FALHAS falha(s) seguida(s). — $NOME_AGENTE" \
      && rm -f "$AVISADO"
  fi
  rm -f "$CONTA"
  exit 0
fi

FALHAS=$((FALHAS + 1))
echo "$FALHAS" > "$CONTA"
echo "$(agora) FALHOU (código $CODIGO), $FALHAS seguida(s)" >> "$LOG"

if [ "$PAUSAR" -gt 0 ] && [ "$FALHAS" -ge "$PAUSAR" ]; then
  touch "$PAUSA"
  avisar "⏸️ Pausei a rotina \"$NOME\": falhou $FALHAS vezes seguidas (último código $CODIGO). Ela fica parada até a gente olhar. — $NOME_AGENTE" \
    && touch "$PAUSA_AVISADA" "$AVISADO"
elif [ "$FALHAS" -ge "$AVISAR" ] && [ ! -f "$AVISADO" ]; then
  # Também tenta de novo quando o aviso anterior não foi entregue.
  avisar "⚠️ A rotina \"$NOME\" falhou ($FALHAS vez(es) seguida(s), código $CODIGO). Se continuar falhando, ela é pausada em $PAUSAR falhas. — $NOME_AGENTE" \
    && touch "$AVISADO"
fi
exit "$CODIGO"
